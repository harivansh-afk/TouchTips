@testable import TouchTips
import TouchTipsCore
import XCTest

@MainActor
final class PlaceSheetTests: XCTestCase {
    func testRemovingPeopleUpdatesCountDatesAndRowsTogether() async throws {
        let database = try AppDatabase.inMemory()
        let placeID = try seedPlace(in: database)
        let oldDate = Date(timeIntervalSince1970: 1_000_000_000)
        let newDate = Date(timeIntervalSince1970: 1_700_000_000)
        try Ingest.addExact(contactID: "old", name: "Old", at: oldDate, placeID: placeID, to: database)
        try Ingest.addExact(contactID: "new", name: "New", at: newDate, placeID: placeID, to: database)
        let observation = ValueObservation.tracking { db in
            try Person.rows(atPlaces: [placeID]).fetchAll(db)
        }
        var values = observation.values(in: database.reader).makeAsyncIterator()
        let initialRows = try await values.next()
        let initial = try PlaceSheetContent(rows: XCTUnwrap(initialRows))
        XCTAssertEqual(initial.people, 2)
        XCTAssertEqual(initial.first, oldDate)
        XCTAssertEqual(initial.last, newDate)
        XCTAssertEqual(initial.sections.first?.rows.map(\.id), ["new", "old"])

        // The person still exists, but the user removed their place in the meeting editor.
        try Ingest.setUserMeet(
            contactID: "old", start: oldDate, end: oldDate, precision: .exact,
            placeID: nil, now: .now, to: database
        )
        let remainingRows = try await values.next()
        let remaining = try PlaceSheetContent(rows: XCTUnwrap(remainingRows))
        XCTAssertEqual(remaining.people, 1)
        XCTAssertEqual(remaining.first, newDate)
        XCTAssertEqual(remaining.last, newDate)
        XCTAssertEqual(remaining.sections.first?.rows.map(\.id), ["new"])
        XCTAssertEqual(remaining.subtitle, "1 person · \(Format.yearSpan(newDate, newDate))")

        _ = try await database.writer.write { try Person.deleteOne($0, key: "new") }
        let emptyRows = try await values.next()
        let empty = try PlaceSheetContent(rows: XCTUnwrap(emptyRows))
        XCTAssertEqual(empty.people, 0)
        XCTAssertTrue(empty.sections.isEmpty)
        XCTAssertNil(empty.first)
        XCTAssertNil(empty.last)
        XCTAssertEqual(empty.title, "No meetings here")
        XCTAssertEqual(empty.subtitle, "0 people")
    }

    func testPlaceRenameRefreshesHeaderAndSectionWithoutMembershipChange() async throws {
        let database = try AppDatabase.inMemory()
        let placeID = try seedPlace(in: database)
        try Ingest.addExact(contactID: "a", name: "Alice", at: .now, placeID: placeID, to: database)
        let observation = ValueObservation.tracking { db in
            try Person.rows(atPlaces: [placeID]).fetchAll(db)
        }
        var values = observation.values(in: database.reader).makeAsyncIterator()
        let initialRows = try await values.next()
        let initial = try PlaceSheetContent(rows: XCTUnwrap(initialRows))
        XCTAssertEqual(initial.title, Format.coordinates(38, -78))

        _ = try await database.writer.write { db in
            try Place.filter(key: placeID).updateAll(db, Place.Columns.name.set(to: "Named cafe"))
        }
        let renamedRows = try await values.next()
        let renamed = try PlaceSheetContent(rows: XCTUnwrap(renamedRows))
        XCTAssertEqual(renamed.title, "Named cafe")
        XCTAssertEqual(renamed.sections.first?.title, "Named cafe")
        XCTAssertEqual(renamed.people, initial.people)
        XCTAssertEqual(renamed.sections.first?.rows.map(\.id), ["a"])
    }

    private func seedPlace(in database: AppDatabase) throws -> Int64 {
        try database.writer.write { db in
            try XCTUnwrap(Place.findOrCreate(db, key: "test-place", latitude: 38, longitude: -78).id)
        }
    }
}
