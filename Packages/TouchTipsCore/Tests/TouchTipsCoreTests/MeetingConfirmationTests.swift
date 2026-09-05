import Foundation
import GRDB
import Testing
@testable import TouchTipsCore

struct MeetingConfirmationTests {
    private func suggestion(in db: AppDatabase) throws -> Meet {
        let start = t("2026-09-01T09:00")
        try Ingest.apply(ContactChangeSet(token: Data([1])), now: start, to: db)
        try Ingest.apply(
            ContactChangeSet(added: [ContactSnapshot(contactID: "a", name: "Alice")], token: Data([2])),
            now: t("2026-09-02T12:00"), to: db
        )
        return try db.reader.read { try #require(try Meet.fetchOne($0, key: "a")) }
    }

    @Test func editingOneFieldDoesNotConfirmTheOtherAndSurvivesReresolution() throws {
        let db = try AppDatabase.inMemory()
        let before = try suggestion(in: db)
        let place = try db.writer.write {
            try Place.findOrCreate($0, key: "cafe", latitude: 1, longitude: 2)
        }
        try Ingest.setUserMeetPlace(contactID: "a", placeID: place.id, now: before.end, to: db)
        try Ingest.reresolveAll(now: before.end, to: db)
        let editedPlace = try db.reader.read { try #require(try Meet.fetchOne($0, key: "a")) }
        #expect(editedPlace.placeConfirmed)
        #expect(!editedPlace.dateConfirmed)
        #expect(!editedPlace.isConfirmed)
        #expect(editedPlace.start == before.start && editedPlace.end == before.end)
        #expect(editedPlace.placeID == place.id)

        try Ingest.confirmMeet(contactID: "a", now: before.end, to: db)
        let confirmed = try db.reader.read { try #require(try Meet.fetchOne($0, key: "a")) }
        #expect(confirmed.isConfirmed)
        #expect(confirmed.start == before.start && confirmed.end == before.end)
    }

    @Test func editingDateDoesNotAcceptSuggestedPlaceOrUnknownPlace() throws {
        let db = try AppDatabase.inMemory()
        let before = try suggestion(in: db)
        try Ingest.setUserMeetDate(
            contactID: "a", start: before.start, end: before.start, precision: .day, now: before.end, to: db
        )
        let edited = try db.reader.read { try #require(try Meet.fetchOne($0, key: "a")) }
        #expect(edited.dateConfirmed)
        #expect(!edited.placeConfirmed)
        #expect(!edited.isConfirmed)
    }

    @Test func forgetPreservesContactAndCannotBeRecreatedByRescanOrVisits() throws {
        let db = try AppDatabase.inMemory()
        let before = try suggestion(in: db)
        try Ingest.setNote(contactID: "a", note: "A note", to: db)
        try Ingest.forgetPerson(contactID: "a", to: db)
        try Ingest.apply(
            ContactChangeSet(added: [ContactSnapshot(contactID: "a", name: "Alice")], token: Data([3])),
            now: before.end, to: db
        )
        try Ingest.apply(
            ContactChangeSet(
                added: [ContactSnapshot(contactID: "a", name: "Alice")],
                token: Data([4]),
                isSnapshot: true
            ),
            now: before.end, to: db
        )
        try Ingest.recordLiveVisit(
            LiveVisit(latitude: 1, longitude: 2, accuracyMeters: 10, arrival: before.start, departure: before.end),
            now: before.end, to: db
        )
        try Ingest.reresolveAll(now: before.end, to: db)
        let row = try db.reader.read { try #require(try Person.row(contactID: "a").fetchOne($0)) }
        #expect(row.person.name == "Alice")
        #expect(row.person.note == nil && row.meet == nil)
        #expect(try db.reader.read { try PendingNotice.fetchCount($0) } == 0)
    }

    @Test func failedForgetRollsBackMeetingNoteAndNotificationTogether() throws {
        let db = try AppDatabase.inMemory()
        _ = try suggestion(in: db)
        try Ingest.setNote(contactID: "a", note: "Keep me", to: db)
        try db.writer.write {
            try $0.execute(sql: """
            CREATE TRIGGER reject_note BEFORE UPDATE OF note ON person
            BEGIN SELECT RAISE(ABORT, 'test failure'); END;
            """)
        }
        #expect(throws: (any Error).self) { try Ingest.forgetPerson(contactID: "a", to: db) }
        let row = try db.reader.read { try #require(try Person.row(contactID: "a").fetchOne($0)) }
        #expect(row.meet != nil && row.person.note == "Keep me")
        #expect(try db.reader.read { try PendingNotice.fetchCount($0) } == 1)
    }

    @Test func mapOnlyEmphasizesConfirmedMeetings() throws {
        let db = try AppDatabase.inMemory()
        let before = try suggestion(in: db)
        let place = try db.writer.write { try Place.findOrCreate($0, key: "cafe", latitude: 1, longitude: 2) }
        try Ingest.setUserMeetPlace(contactID: "a", placeID: place.id, now: before.end, to: db)
        #expect(try db.reader.read { try PlaceSummary.all().fetchOne($0)?.witnessed } == false)
        try Ingest.confirmMeet(contactID: "a", now: before.end, to: db)
        #expect(try db.reader.read { try PlaceSummary.all().fetchOne($0)?.witnessed } == true)
    }

    @Test func legacyMigrationPreservesEditsAndRepairsAutomaticFixes() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v4-notification-outbox")
        try queue.write { db in
            try db.execute(sql: """
            INSERT INTO person (contactID, name, beforeInstall, createdAt, note)
            VALUES ('edited', 'Alice', 0, 100, 'keep this'), ('auto', 'Bob', 0, 100, NULL),
                   ('added', 'Carol', 0, 100, NULL);
            INSERT INTO place (id, key, latitude, longitude) VALUES (1, 'cafe', 1, 2);
            INSERT INTO visit (placeID, start, end, source) VALUES (1, 10000, 10000, 'fix');
            INSERT INTO meet (contactID, start, end, precision, placeID, tier, userSet,
                              addSeenStart, addSeenEnd, computedAt)
            VALUES ('edited', 100, 10000, 'month', 1, 0, 1, 100, 10000, 10000),
                   ('auto', 10000, 10000, 'exact', 1, 1, 0, 100, 10000, 10000),
                   ('added', 100, 100, 'exact', NULL, 0, 1, 100, 100, 100);
            """)
        }
        let db = try AppDatabase(queue)
        let edited = try db.reader.read { try #require(try Person.row(contactID: "edited").fetchOne($0)) }
        #expect(edited.person.note == "keep this")
        #expect(edited.meet?.userSet == true && edited.meet?.isConfirmed == false)
        #expect(edited.meet?.placeID == 1 && edited.meet?.precision == .month)
        let automatic = try db.reader.read { try #require(try Meet.fetchOne($0, key: "auto")) }
        #expect(automatic.placeID == nil && !automatic.isConfirmed)
        #expect(automatic.start == Date(timeIntervalSince1970: 100))
        #expect(automatic.end == Date(timeIntervalSince1970: 10000))
        #expect(try db.reader.read { try Meet.fetchOne($0, key: "added")?.isConfirmed } == true)
        // Reopening must not reset new confirmation state.
        try Ingest.confirmMeet(contactID: "edited", now: .now, to: db)
        let reopened = try AppDatabase(queue)
        #expect(try reopened.reader.read { try Meet.fetchOne($0, key: "edited")?.isConfirmed } == true)
    }
}
