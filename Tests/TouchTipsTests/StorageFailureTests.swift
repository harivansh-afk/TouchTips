@testable import TouchTips
import TouchTipsCore
import XCTest

@MainActor
final class StorageFailureTests: XCTestCase {
    func testFailedOpenNeverExposesAnEditableAppOrStartsCapture() {
        var attempts = 0
        var starts = 0
        let session = AppSession(open: {
            attempts += 1
            throw CocoaError(.fileReadNoPermission)
        }, start: { _ in starts += 1 })

        session.retry()
        session.retry()

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(starts, 0)
        XCTAssertNil(session.app)
    }

    func testRetryUsesRecoveredDatabaseAndStartsOnlyOnce() throws {
        let db = try AppDatabase.inMemory()
        try Ingest.addExact(contactID: "saved", name: "Saved contact", at: .now, placeID: nil, to: db)
        try Ingest.setNote(contactID: "saved", note: "Existing note", to: db)
        var unavailable = true
        var attempts = 0
        var starts = 0
        let session = AppSession(open: {
            attempts += 1
            if unavailable {
                throw CocoaError(.fileReadUnknown)
            }
            return db
        }, start: { _ in starts += 1 })

        session.retry()
        XCTAssertNil(session.app)
        XCTAssertEqual(starts, 0)
        unavailable = false
        session.retry()
        session.retry()

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(starts, 1)
        let app = try XCTUnwrap(session.app)
        XCTAssertTrue(app.database === db)
        let note = try app.database.reader.read { try Person.fetchOne($0, key: "saved")?.note }
        XCTAssertEqual(note, "Existing note")
    }
}
