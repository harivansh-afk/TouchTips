import Contacts
@testable import TouchTips
import TouchTipsCore
import UserNotifications
import XCTest

@MainActor
final class NotificationTests: XCTestCase {
    func testConcurrentWakeWaitsForActiveCapture() async throws {
        let db = try AppDatabase.inMemory()
        try Ingest.addExact(contactID: "blocked", name: "Blocked", at: .now, placeID: nil, to: db)
        var submission: CheckedContinuation<Void, Never>?
        let notifier = Notifier(database: db, delivery: NotificationDelivery(
            authorization: { .authorized }, submittedIDs: { [] },
            submit: { _ in await withCheckedContinuation { submission = $0 } }
        ))
        let capture = CaptureCoordinator(database: db, notifier: notifier)
        let first = Task { await capture.tick(.user) }
        for _ in 0 ..< 50 {
            if submission != nil {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNotNil(submission)
        var secondReturned = false
        let second = Task {
            await capture.tick(.refresh)
            secondReturned = true
        }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(secondReturned, "A background wake must not report completion while the scan is still running")
        submission?.resume()
        await first.value
        await second.value
        XCTAssertTrue(secondReturned)
    }

    func testDeniedAndFailedSubmissionRemainQueuedThenRetryOnce() async throws {
        let db = try AppDatabase.inMemory()
        try Ingest.addExact(contactID: "retry", name: "Retry", at: .now, placeID: nil, to: db)
        var permission = UNAuthorizationStatus.denied
        var fail = true
        var attempts = 0
        let notifier = Notifier(database: db, delivery: NotificationDelivery(
            authorization: { permission }, submittedIDs: { [] }, submit: { _ in
                attempts += 1
                if fail {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
        ))
        await notifier.deliverPending()
        XCTAssertEqual(attempts, 0)
        permission = .authorized
        await notifier.deliverPending()
        XCTAssertEqual(attempts, 1)
        let queued = try await db.reader.read { try PendingNotice.fetchCount($0) }
        let timing = try await db.reader.read { try $0.value(for: .lastNotice) }
        XCTAssertEqual(queued, 1)
        XCTAssertNil(timing)
        fail = false
        await notifier.deliverPending()
        await notifier.deliverPending()
        XCTAssertEqual(attempts, 2)
        let remaining = try await db.reader.read { try PendingNotice.fetchCount($0) }
        XCTAssertEqual(remaining, 0)
    }

    func testAlreadyDeliveredRequestIsAcknowledgedWithoutAnotherBanner() async throws {
        let db = try AppDatabase.inMemory()
        try Ingest.addExact(contactID: "sent", name: "Sent", at: .now, placeID: nil, to: db)
        let notifier = Notifier(database: db, delivery: NotificationDelivery(
            authorization: { .authorized }, submittedIDs: { ["meet-sent"] },
            submit: { _ in XCTFail("Already submitted notification was posted again") }
        ))
        await notifier.deliverPending()
        let remaining = try await db.reader.read { try PendingNotice.fetchCount($0) }
        XCTAssertEqual(remaining, 0)
    }

    func testOnlyOpenActionsNavigateAndConfirmPersists() throws {
        let db = try AppDatabase.inMemory()
        try Ingest.addExact(contactID: "a", name: "Alice", at: .now, placeID: nil, to: db)
        let notifier = Notifier(database: db)
        notifier.handle(action: UNNotificationDismissActionIdentifier, contactID: "a")
        notifier.handle(action: "unknown", contactID: "a")
        XCTAssertNil(notifier.pendingPerson)
        notifier.handle(action: "confirm", contactID: "a")
        XCTAssertNil(notifier.pendingPerson)
        XCTAssertTrue(try db.reader.read { try Meet.fetchOne($0, key: "a")!.userSet })
        notifier.handle(action: UNNotificationDefaultActionIdentifier, contactID: "a")
        XCTAssertEqual(notifier.pendingPerson, "a")
        notifier.pendingPerson = nil
        notifier.handle(action: "fix", contactID: "a")
        XCTAssertEqual(notifier.pendingPerson, "a")
        notifier.handle(action: "notAMeeting", contactID: "a")
        XCTAssertNil(try db.reader.read { try Meet.fetchOne($0, key: "a") })
    }

    func testNotificationRouteReplacesExistingPathWithoutZoom() {
        let router = Router()
        router.selectedTab = .map
        router.paths[.people] = [.undocumented, .person("old")]
        router.openNotification("new")
        XCTAssertEqual(router.selectedTab, .people)
        XCTAssertEqual(router.paths[.people], [.person("new", zoom: false)])
        router.back()
        XCTAssertTrue(router.isOnRoot)
    }

    func testRealContactHistoryAndListener() async throws {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            throw XCTSkip("Grant full Contacts access on the isolated simulator before running.")
        }
        let db = try AppDatabase.inMemory()
        let notifier = Notifier(database: db)
        let capture = CaptureCoordinator(database: db, notifier: notifier)
        // Use only the contact observer: no second BGTask registration in the test host.
        capture.startObservingContacts()
        await capture.tick(.user)
        let contact = CNMutableContact()
        contact.organizationName = "TouchTips Test \(UUID().uuidString)"
        let store = CNContactStore()
        let save = CNSaveRequest()
        save.add(contact, toContainerWithIdentifier: nil)
        try store.execute(save)
        let contactID = contact.identifier
        defer {
            let remove = CNSaveRequest()
            remove.delete(contact)
            try? store.execute(remove)
        }
        // No manual tick here: this must arrive through CNContactStoreDidChange and the debounce.
        var found = false
        for _ in 0 ..< 80 {
            if try await db.reader.read({ try Person.fetchOne($0, key: contactID) }) != nil {
                found = true
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(found, "The retained listener did not ingest the external Contacts save")
        let row = try await db.reader.read { try Person.fetchOne($0, key: contactID) }
        XCTAssertEqual(row?.name, contact.organizationName)
        XCTAssertEqual(row?.beforeInstall, false)
        capture.stopObservingContacts()
    }
}
