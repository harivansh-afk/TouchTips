@testable import TouchTips
import TouchTipsCore
import UserNotifications
import XCTest

/// A notice says the place known when it is posted, and "That's right" accepts only that place.
@MainActor
final class PlaceNoticeTests: XCTestCase {
    private let cafe = Place(key: "a:cafe", latitude: 30.26, longitude: -97.74, name: "Grit Coffee")

    private func recorder(_ requests: @escaping (UNNotificationRequest) -> Void) -> NotificationDelivery {
        NotificationDelivery(authorization: { .authorized }, submittedIDs: { [] }, submit: { requests($0) })
    }

    /// One Contacts snapshot, then a scan that finds Alice.
    private func contacts() -> CaptureContacts {
        CaptureContacts(authorized: { true }, changes: { token in
            token == nil
                ? ContactChangeSet(token: Data([1]), isSnapshot: true)
                : ContactChangeSet(added: [ContactSnapshot(contactID: "a", name: "Alice")], token: Data([2]))
        })
    }

    func testAScanWhileOpenAnnouncesThePlaceFoundBeforePosting() async throws {
        let db = try AppDatabase.inMemory()
        var posted: [UNNotificationRequest] = []
        let notifier = Notifier(database: db, delivery: recorder { posted.append($0) })
        let capture = CaptureCoordinator(database: db, notifier: notifier, contacts: contacts())
        capture.beforeAnnouncing = { [cafe] in
            _ = try? Ingest.suggestPlace(
                cafe, forContactsSeenSince: .distantPast, now: .now, to: db
            )
        }
        await capture.tick(.launch)
        await capture.tick(.contacts)

        let notice = try XCTUnwrap(posted.first)
        XCTAssertEqual(posted.count, 1)
        XCTAssertEqual(notice.content.title, "Met Alice?")
        XCTAssertTrue(notice.content.body.hasPrefix("Grit Coffee @ "), notice.content.body)
        let placeID = try await db.reader.read { try XCTUnwrap(try Meet.fetchOne($0, key: "a")?.placeID) }
        XCTAssertEqual((notice.content.userInfo["placeID"] as? NSNumber)?.int64Value, placeID)
    }

    func testANoticeWithoutAPlaceDoesNotConfirmOneSuggestedLater() async throws {
        let db = try AppDatabase.inMemory()
        var posted: [UNNotificationRequest] = []
        let notifier = Notifier(database: db, delivery: recorder { posted.append($0) })
        let capture = CaptureCoordinator(database: db, notifier: notifier, contacts: contacts())
        await capture.tick(.launch)
        await capture.tick(.contacts)

        let notice = try XCTUnwrap(posted.first)
        XCTAssertTrue(notice.content.body.hasSuffix("Where?"), notice.content.body)
        XCTAssertNil(notice.content.userInfo["placeID"])

        try Ingest.suggestPlace(cafe, forContactsSeenSince: .distantPast, now: .now, to: db)
        notifier.handle(action: "confirm", contactID: "a", shownPlaceID: nil)
        let meet = try await db.reader.read { try XCTUnwrap(try Meet.fetchOne($0, key: "a")) }
        XCTAssertTrue(meet.dateConfirmed)
        XCTAssertFalse(meet.placeConfirmed)
        XCTAssertNotNil(meet.placeID)
    }
}
