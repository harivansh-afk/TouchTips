import BackgroundTasks
import CoreLocation
@testable import TouchTips
import TouchTipsCore
import UserNotifications
import XCTest

@MainActor
final class NotificationReliabilityTests: XCTestCase {
    func testLaterWakeCannotPostponeAnAlreadyScheduledContactScan() async throws {
        let db = try AppDatabase.inMemory()
        var reads = 0
        let capture = CaptureCoordinator(database: db, notifier: silentNotifier(db), contacts: CaptureContacts(
            authorized: { true }, changes: { _ in
                reads += 1
                return ContactChangeSet(token: Data([1]))
            }
        ))
        capture.scheduleTick(.contacts, after: 0.02)
        capture.scheduleTick(.movement, after: 20)
        await waitUntil { reads > 0 }
        capture.stopObservingContacts()
        XCTAssertEqual(reads, 1)
    }

    func testTransientContactReadRetriesFromTheUnchangedToken() async throws {
        let db = try AppDatabase.inMemory()
        try Ingest.apply(ContactChangeSet(token: Data([1])), now: .now, to: db)
        var tokens: [Data?] = []
        let capture = CaptureCoordinator(
            database: db, notifier: silentNotifier(db),
            contacts: CaptureContacts(authorized: { true }, changes: {
                tokens.append($0)
                if tokens.count == 1 {
                    throw CocoaError(.fileReadUnknown)
                }
                return ContactChangeSet(added: [.init(contactID: "a", name: "A")], token: Data([2]))
            }), retryDelays: [.zero]
        )
        let success = await capture.tick(.foreground)
        XCTAssertTrue(success)
        XCTAssertEqual(tokens, [Data([1]), Data([1])])
        XCTAssertEqual(try queued(in: db), ["a"])
    }

    func testWakeDuringCancelledScanRunsAfterItUnwinds() async throws {
        let db = try AppDatabase.inMemory()
        try Ingest.apply(ContactChangeSet(token: Data([1])), now: .now, to: db)
        var pending: CheckedContinuation<ContactChangeSet, Never>?
        var reads = 0
        let capture = CaptureCoordinator(database: db, notifier: silentNotifier(db), contacts: CaptureContacts(
            authorized: { true }, changes: { _ in
                reads += 1
                if reads == 1 {
                    return await withCheckedContinuation { pending = $0 }
                }
                return ContactChangeSet(added: [.init(contactID: "a", name: "A")], token: Data([2]))
            }
        ))
        let work = Task { await capture.tick(.contacts) }
        await waitUntil { pending != nil }
        work.cancel()
        capture.scheduleTick(.foreground, after: 0)
        pending?.resume(returning: ContactChangeSet(token: Data([2])))
        _ = await work.value
        await waitUntil { (try? self.queued(in: db)) == ["a"] }
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(try queued(in: db), ["a"])
    }

    func testFailingNoticeDoesNotBlockOtherPeople() async throws {
        let db = try AppDatabase.inMemory()
        try add("a", to: db)
        try add("b", to: db)
        var attempts: [String] = []
        let notifier = Notifier(database: db, delivery: NotificationDelivery(
            authorization: { .authorized }, submittedIDs: { [] }, submit: {
                attempts.append($0.identifier)
                if $0.identifier == "meet-a" {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
        ), retryDelays: [])
        await notifier.deliverPending()
        XCTAssertEqual(attempts, ["meet-a", "meet-b"])
        XCTAssertEqual(try queued(in: db), ["a"])
    }

    func testTransientFailureRetriesWithoutAnotherWake() async throws {
        let db = try AppDatabase.inMemory()
        try add("retry", to: db)
        var attempts = 0
        let notifier = Notifier(database: db, delivery: NotificationDelivery(
            authorization: { .authorized }, submittedIDs: { [] }, submit: { _ in
                attempts += 1
                if attempts == 1 {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
        ), retryDelays: [.zero])
        await notifier.deliverPending()
        XCTAssertEqual(attempts, 2)
        XCTAssertTrue(try queued(in: db).isEmpty)
    }

    func testConcurrentDeliveryWaitsUntilSubmissionFinishes() async throws {
        let db = try AppDatabase.inMemory()
        try add("a", to: db)
        var submission: CheckedContinuation<Void, Never>?
        let notifier = Notifier(database: db, delivery: NotificationDelivery(
            authorization: { .authorized }, submittedIDs: { [] }, submit: { _ in
                await withCheckedContinuation { submission = $0 }
            }
        ))
        let first = Task { await notifier.deliverPending() }
        await waitUntil { submission != nil }
        var secondReturned = false
        let second = Task {
            await notifier.deliverPending()
            secondReturned = true
        }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(secondReturned)
        submission?.resume()
        await first.value
        await second.value
        XCTAssertTrue(secondReturned)
        XCTAssertTrue(try queued(in: db).isEmpty)
    }

    func testForgottenPersonInReadBatchIsNotPosted() async throws {
        let db = try AppDatabase.inMemory()
        try add("a", to: db)
        try add("b", to: db)
        var submitted: [String] = []
        let notifier = Notifier(database: db, delivery: NotificationDelivery(
            authorization: { .authorized }, submittedIDs: { [] }, submit: {
                submitted.append($0.identifier)
                try Ingest.forgetPerson(contactID: "b", to: db)
            }
        ))
        await notifier.deliverPending()
        XCTAssertEqual(submitted, ["meet-a"])
    }

    func testNoticeForgottenDuringSubmissionIsWithdrawn() async throws {
        let db = try AppDatabase.inMemory()
        try add("a", to: db)
        var removed: [String] = []
        let notifier = Notifier(database: db, delivery: NotificationDelivery(
            authorization: { .authorized }, submittedIDs: { [] }, submit: { _ in
                try Ingest.forgetPerson(contactID: "a", to: db)
            }, remove: { removed += $0 }
        ))
        await notifier.deliverPending()
        XCTAssertEqual(removed, ["meet-a"])
        XCTAssertTrue(try queued(in: db).isEmpty)
    }

    func testLocationCannotDelayContactCommitOrNotification() async throws {
        let db = try AppDatabase.inMemory()
        try Ingest.apply(ContactChangeSet(token: Data([1])), now: .now, to: db)
        var fix: CheckedContinuation<CLLocation?, Never>?
        var posted = false
        var finished = false
        let notifier = Notifier(database: db, delivery: NotificationDelivery(
            authorization: { .authorized }, submittedIDs: { [] }, submit: { _ in posted = true }
        ))
        let capture = CaptureCoordinator(
            database: db, notifier: notifier,
            contacts: CaptureContacts(authorized: { true }, changes: { _ in
                ContactChangeSet(added: [.init(contactID: "a", name: "A")], token: Data([2]))
            }),
            location: CaptureLocation(authorized: { true }, fix: { _ in
                await withCheckedContinuation { fix = $0 }
            })
        )
        let work = Task {
            await capture.tick(.contacts)
            finished = true
        }
        await waitUntil { fix != nil && finished }
        XCTAssertTrue(finished, "Optional location held the capture task open")
        XCTAssertTrue(posted, "Optional location blocked notification delivery")
        let token = try await db.reader.read { try $0.value(for: .contactsHistoryToken) }
        let person = try await db.reader.read { try Person.fetchOne($0, key: "a") }
        XCTAssertEqual(token, Data([2]))
        XCTAssertNotNil(person)
        fix?.resume(returning: nil)
        await work.value
    }

    func testDeletionIsReconciledBeforeDrainingNotices() async throws {
        let db = try AppDatabase.inMemory()
        try add("deleted", to: db)
        let notifier = Notifier(database: db, delivery: NotificationDelivery(
            authorization: { .authorized }, submittedIDs: { [] },
            submit: { _ in XCTFail("A deleted contact was notified before Contacts reconciliation") }
        ))
        let capture = CaptureCoordinator(database: db, notifier: notifier, contacts: CaptureContacts(
            authorized: { true }, changes: { _ in
                ContactChangeSet(deletedIDs: ["deleted"], token: Data([2]))
            }
        ))
        let success = await capture.tick(.foreground)
        XCTAssertTrue(success)
        XCTAssertTrue(try queued(in: db).isEmpty)
    }

    func testContactFailureReportsFailureButStillDrainsDurableNotices() async throws {
        let db = try AppDatabase.inMemory()
        try add("a", to: db)
        var posted = false
        let notifier = Notifier(database: db, delivery: NotificationDelivery(
            authorization: { .authorized }, submittedIDs: { [] }, submit: { _ in posted = true }
        ))
        let capture = CaptureCoordinator(database: db, notifier: notifier, contacts: CaptureContacts(
            authorized: { true }, changes: { _ in throw CocoaError(.fileReadUnknown) }
        ))
        let success = await capture.tick(.refresh)
        XCTAssertFalse(success)
        XCTAssertTrue(posted)
        let token = try await db.reader.read { try $0.value(for: .contactsHistoryToken) }
        XCTAssertNil(token)
    }

    func testRefreshKeepsEarlierRequestAndAdvancesOldFourHourRequest() async throws {
        let db = try AppDatabase.inMemory()
        let request = BGAppRefreshTaskRequest(identifier: CaptureCoordinator.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        var requests: [BGTaskRequest] = [request]
        var submissions = 0
        let capture = CaptureCoordinator(
            database: db, notifier: Notifier(database: db),
            refresh: CaptureRefresh(pending: { requests }, submit: {
                submissions += 1
                requests = [$0]
            })
        )
        await capture.scheduleRefresh().value
        await capture.scheduleRefresh().value
        XCTAssertEqual(submissions, 0)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        await capture.scheduleRefresh().value
        XCTAssertEqual(submissions, 1)
        XCTAssertLessThanOrEqual(try XCTUnwrap(requests.first?.earliestBeginDate).timeIntervalSinceNow, 15 * 60)
        await capture.scheduleRefresh().value
        XCTAssertEqual(submissions, 1)
    }

    private func add(_ id: String, to db: AppDatabase) throws {
        try Ingest.addExact(contactID: id, name: id, at: Date(timeIntervalSince1970: 1000), placeID: nil, to: db)
    }

    private func silentNotifier(_ db: AppDatabase) -> Notifier {
        Notifier(database: db, delivery: NotificationDelivery(
            authorization: { .denied }, submittedIDs: { [] }, submit: { _ in }
        ))
    }

    private func queued(in db: AppDatabase) throws -> [String] {
        try db.reader.read { try PendingNotice.all().fetchAll($0).map(\.contactID) }
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0 ..< 200 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
