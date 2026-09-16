import BackgroundTasks
import Contacts
@testable import TouchTips
import TouchTipsCore
import XCTest

@MainActor
final class ContactCheckTests: XCTestCase {
    func testFullAccessAndExistingBaselineAreRequiredWithoutReadingContacts() async throws {
        let fixture = try Fixture(baseline: false)
        var authorized = false
        var reads = 0
        let capture = fixture.capture(authorized: { authorized }) { _ in
            reads += 1
            return ContactChangeSet(token: Data([2]), isSnapshot: true)
        }
        await expect(.contactsAccessRequired) { try await capture.checkForNewContacts() }
        authorized = true
        await expect(.setupRequired) { try await capture.checkForNewContacts() }
        let refreshed = await capture.tick(.refresh)
        XCTAssertFalse(refreshed)
        XCTAssertEqual(reads, 0)
        XCTAssertNil(fixture.defaults.object(forKey: CaptureCoordinator.lastShortcutCheckKey))
    }

    func testHeadlessStartDoesNotScanOrObserveContacts() async throws {
        let fixture = try Fixture(baseline: false)
        var reads = 0
        let capture = fixture.capture { _ in
            reads += 1
            return ContactChangeSet(token: Data([2]), isSnapshot: true)
        }
        capture.start(checkOnLaunch: false)
        NotificationCenter.default.post(name: .CNContactStoreDidChange, object: nil)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(reads, 0)
        await expect(.setupRequired) { try await capture.checkForNewContacts() }
        capture.stopObservingContacts()
    }

    func testZeroChangesIsSuccessAndStoresEpochTimestamp() async throws {
        let fixture = try Fixture()
        var tokens: [Data?] = []
        let capture = fixture.capture { token in
            tokens.append(token)
            return ContactChangeSet(token: Data([2]))
        }
        let result = try await capture.checkForNewContacts()
        XCTAssertEqual(tokens, [Data([1])])
        XCTAssertEqual(
            fixture.defaults.double(forKey: CaptureCoordinator.lastShortcutCheckKey),
            result.checkedAt.timeIntervalSince1970
        )
        let count = try await fixture.db.reader.read { try Person.fetchCount($0) }
        XCTAssertEqual(count, 0)
    }

    func testFailureAndCancellationDoNotOverwriteLastSuccess() async throws {
        let fixture = try Fixture()
        fixture.defaults.set(123.0, forKey: CaptureCoordinator.lastShortcutCheckKey)
        let failing = fixture.capture { _ in throw CocoaError(.fileReadUnknown) }
        await expect(.scanFailed) { try await failing.checkForNewContacts() }
        var reading = false
        let capture = fixture.capture { _ in
            reading = true
            try await Task.sleep(for: .seconds(30))
            return ContactChangeSet(token: Data([2]))
        }
        let work = Task { try await capture.checkForNewContacts() }
        await eventually { reading }
        work.cancel()
        await expect(.cancelled) { try await work.value }
        XCTAssertEqual(fixture.defaults.double(forKey: CaptureCoordinator.lastShortcutCheckKey), 123)
        let token = try await fixture.db.reader.read { try $0.value(for: .contactsHistoryToken) }
        XCTAssertEqual(token, Data([1]))
    }

    func testPermissionDowngradeDuringReadCannotDeleteSavedContacts() async throws {
        let fixture = try Fixture()
        try Ingest.addExact(contactID: "saved", name: "Saved", at: .now, placeID: nil, to: fixture.db)
        try Ingest.setNote(contactID: "saved", note: "Keep this", to: fixture.db)
        var authorized = true
        let capture = fixture.capture(authorized: { authorized }) { _ in
            authorized = false
            return ContactChangeSet(token: Data([2]), isSnapshot: true)
        }
        await expect(.contactsAccessRequired) { try await capture.checkForNewContacts() }
        let person = try await fixture.db.reader.read { try Person.fetchOne($0, key: "saved") }
        XCTAssertEqual(person?.note, "Keep this")
        let token = try await fixture.db.reader.read { try $0.value(for: .contactsHistoryToken) }
        XCTAssertEqual(token, Data([1]))
        XCTAssertNil(fixture.defaults.object(forKey: CaptureCoordinator.lastShortcutCheckKey))
    }

    func testConcurrentChecksAwaitDeliveryAndUseFreshCursorForFollowup() async throws {
        let fixture = try Fixture()
        var read: CheckedContinuation<ContactChangeSet, Never>?
        var delivery: CheckedContinuation<Void, Never>?
        var tokens: [Data?] = []
        var submissions: [String] = []
        let capture = fixture.capture(submit: { id in
            submissions.append(id)
            await withCheckedContinuation { delivery = $0 }
        }) { token in
            tokens.append(token)
            if tokens.count == 1 {
                return await withCheckedContinuation { read = $0 }
            }
            return ContactChangeSet(token: Data([3]))
        }
        let first = Task { try await capture.checkForNewContacts() }
        await eventually { read != nil }
        let second = Task { try await capture.checkForNewContacts() }
        // Let the second preflight join the suspended scan before returning its first delta.
        try await Task.sleep(for: .milliseconds(30))
        read?.resume(returning: ContactChangeSet(
            added: [.init(contactID: "new", name: "New")], token: Data([2])
        ))
        await eventually { delivery != nil }
        XCTAssertNil(
            fixture.defaults.object(forKey: CaptureCoordinator.lastShortcutCheckKey),
            "A completed scan alone must not report success before delivery returns"
        )
        delivery?.resume()
        _ = try await first.value
        _ = try await second.value
        XCTAssertEqual(tokens, [Data([1]), Data([2])])
        XCTAssertEqual(submissions, ["meet-new"])
        let token = try await fixture.db.reader.read { try $0.value(for: .contactsHistoryToken) }
        XCTAssertEqual(token, Data([3]))
        let pending = try await fixture.db.reader.read { try PendingNotice.fetchCount($0) }
        XCTAssertEqual(pending, 0)
    }

    private func expect(
        _ expected: ContactCheckError,
        operation: () async throws -> ContactCheckResult,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? ContactCheckError, expected, file: file, line: line)
        }
    }

    private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0 ..< 200 {
            if predicate() {
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Expected async capture work", file: file, line: line)
    }
}

@MainActor
private final class Fixture {
    let db: AppDatabase
    let defaults: UserDefaults
    let suite = "ContactCheckTests.\(UUID())"

    init(baseline: Bool = true) throws {
        db = try AppDatabase.inMemory()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        if baseline {
            try Ingest.apply(ContactChangeSet(token: Data([1])), now: .now, to: db)
        }
    }

    isolated deinit { defaults.removePersistentDomain(forName: suite) }

    func capture(
        authorized: @escaping () -> Bool = { true },
        submit: @escaping (String) async -> Void = { _ in },
        changes: @escaping (Data?) async throws -> ContactChangeSet
    ) -> CaptureCoordinator {
        let notifier = Notifier(database: db, delivery: NotificationDelivery(
            authorization: { .authorized }, submittedIDs: { [] }, submit: { await submit($0.identifier) }
        ))
        return CaptureCoordinator(
            database: db, notifier: notifier,
            contacts: CaptureContacts(authorized: authorized, changes: changes),
            location: CaptureLocation(authorized: { true }, fix: { _ in
                XCTFail("Capture must not request location")
                return nil
            }),
            refresh: CaptureRefresh(pending: { [] }, submit: { _ in }),
            retryDelays: [], defaults: defaults
        )
    }
}
