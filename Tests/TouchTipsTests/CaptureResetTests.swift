@testable import TouchTips
import TouchTipsCore
import XCTest

@MainActor
final class CaptureResetTests: XCTestCase {
    func testResetWaitsForOldDeltaThenRestoresFullContactsBaseline() async throws {
        let db = try AppDatabase.inMemory()
        let old = ContactSnapshot(contactID: "old", name: "Existing contact")
        let new = ContactSnapshot(contactID: "new", name: "Added during capture")
        try Ingest.apply(ContactChangeSet(added: [old], token: Data([1])), now: .now, to: db)
        try Ingest.setNote(contactID: old.contactID, note: "Erase this", to: db)
        var pendingDelta: CheckedContinuation<ContactChangeSet, Never>?
        var tokens: [Data?] = []
        let notifier = Notifier(database: db, delivery: NotificationDelivery(
            authorization: { .denied }, submittedIDs: { [] }, submit: { _ in XCTFail("Reset must be silent") }
        ))
        let capture = CaptureCoordinator(database: db, notifier: notifier, contacts: CaptureContacts(
            authorized: { true },
            changes: { token in
                tokens.append(token)
                if tokens.count == 1 {
                    return await withCheckedContinuation { pendingDelta = $0 }
                }
                return ContactChangeSet(added: [old, new], token: Data([3]), isSnapshot: true)
            }
        ))
        let tick = Task { await capture.tick(.contacts) }
        for _ in 0 ..< 200 {
            if pendingDelta != nil {
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNotNil(pendingDelta)
        let reset = Task { try await capture.reset() }
        for _ in 0 ..< 200 {
            if capture.isResetting {
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(capture.isResetting)
        // A foreground wake cannot start another old-token scan while the reset waits.
        await capture.tick(.foreground)
        XCTAssertEqual(tokens.count, 1)
        pendingDelta?.resume(returning: ContactChangeSet(added: [new], token: Data([2])))
        await tick.value
        try await reset.value

        XCTAssertEqual(tokens.count, 2)
        if tokens.count == 2 {
            XCTAssertEqual(tokens[0], Data([1]))
            XCTAssertNil(tokens[1])
        }
        let rows = try await db.reader.read { try Person.rows().fetchAll($0) }
        XCTAssertEqual(Set(rows.map(\.id)), ["old", "new"])
        XCTAssertTrue(rows.allSatisfy { $0.person.beforeInstall && $0.person.note == nil && $0.meet == nil })
        let queued = try await db.reader.read { try PendingNotice.fetchCount($0) }
        XCTAssertEqual(queued, 0)
        XCTAssertFalse(capture.isResetting)
    }

    func testResetClearsCachedVisitAndCannotReuseItForLaterContact() async throws {
        let db = try AppDatabase.inMemory()
        var reads = 0
        let notifier = Notifier(database: db, delivery: NotificationDelivery(
            authorization: { .denied }, submittedIDs: { [] }, submit: { _ in }
        ))
        let capture = CaptureCoordinator(database: db, notifier: notifier, contacts: CaptureContacts(
            authorized: { true }, changes: { _ in
                reads += 1
                return ContactChangeSet(token: Data([UInt8(reads)]), isSnapshot: true)
            }
        ))
        capture.record(LiveVisit(
            latitude: 37, longitude: -122, accuracyMeters: 10,
            arrival: .now.addingTimeInterval(-3600), departure: nil
        ))
        XCTAssertNotNil(capture.currentVisit)
        try await capture.reset()
        XCTAssertNil(capture.currentVisit)
        let visits = try await db.reader.read { try Visit.fetchCount($0) }
        let places = try await db.reader.read { try Place.fetchCount($0) }
        XCTAssertEqual(visits, 0)
        XCTAssertEqual(places, 0)
        try Ingest.apply(
            ContactChangeSet(added: [.init(contactID: "later", name: "Later")], token: Data([9])),
            now: .now, to: db
        )
        let meeting = try await db.reader.read { try Meet.fetchOne($0, key: "later") }
        XCTAssertNil(meeting?.placeID)
        XCTAssertEqual(meeting?.tier, .dateOnly)
    }
}
