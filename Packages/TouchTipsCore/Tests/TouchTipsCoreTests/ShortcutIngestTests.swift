import Foundation
import GRDB
import Testing
@testable import TouchTipsCore

struct ShortcutIngestTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    @Test(arguments: [nil, Data([0])])
    func staleCursorRejectsEveryWrite(expected: Data?) throws {
        let now = t("2026-09-02T09:00")
        try Ingest.apply(ContactChangeSet(token: Data([1])), now: now, expectedToken: nil, to: db)
        try Ingest.addExact(contactID: "keep", name: "Keep", at: now, placeID: nil, to: db)
        try Ingest.setNote(contactID: "keep", note: "A note", to: db)
        let before = try db.reader.read { db in
            (try Person.fetchAll(db), try Meet.fetchAll(db), try PendingNotice.all().fetchAll(db))
        }
        #expect(throws: StaleContactHistory.self) {
            try Ingest.apply(
                ContactChangeSet(
                    added: [ContactSnapshot(contactID: "new", name: "New")],
                    updated: [ContactSnapshot(contactID: "keep", name: "Wrong")],
                    deletedIDs: ["keep"], token: Data([2]), isSnapshot: true
                ),
                now: now.addingTimeInterval(60), expectedToken: expected,
                useLocationEvidence: false, to: db
            )
        }
        try db.reader.read { (db: Database) throws -> Void in
            #expect(try Person.fetchAll(db) == before.0)
            #expect(try Meet.fetchAll(db) == before.1)
            #expect(try PendingNotice.all().fetchAll(db) == before.2)
            #expect(try db.value(for: .contactsHistoryToken) == Data([1]))
            #expect(try db.date(for: .lastTick) == now)
        }
    }

    @Test func nonNilExpectationRejectsMissingCursor() throws {
        #expect(throws: StaleContactHistory.self) {
            try Ingest.apply(
                ContactChangeSet(added: [ContactSnapshot(contactID: "new", name: "New")], token: Data([2])),
                now: t("2026-09-02T09:00"), expectedToken: Data([1]), to: db
            )
        }
        try db.reader.read { (db: Database) throws -> Void in
            #expect(try Person.fetchCount(db) == 0)
            #expect(try db.value(for: .contactsHistoryToken) == nil)
            #expect(try db.date(for: .lastTick) == nil)
        }
    }

    @Test func matchingCursorStillRollsBackOnWriteFailure() throws {
        let now = t("2026-09-02T09:00")
        try Ingest.apply(ContactChangeSet(token: Data([1])), now: now, expectedToken: nil, to: db)
        try db.writer.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_notice BEFORE INSERT ON pendingNotice
                BEGIN SELECT RAISE(ABORT, 'test failure'); END
                """)
        }
        #expect(throws: DatabaseError.self) {
            try Ingest.apply(
                ContactChangeSet(added: [ContactSnapshot(contactID: "new", name: "New")], token: Data([2])),
                now: now.addingTimeInterval(60), expectedToken: Data([1]), useLocationEvidence: false, to: db
            )
        }
        try db.reader.read { (db: Database) throws -> Void in
            #expect(try Person.fetchCount(db) == 0)
            #expect(try Meet.fetchCount(db) == 0)
            #expect(try PendingNotice.fetchCount(db) == 0)
            #expect(try db.value(for: .contactsHistoryToken) == Data([1]))
            #expect(try db.date(for: .lastTick) == now)
        }
    }

    @Test func shortcutDiscoveryIgnoresOngoingVisitWithoutErasingHistory() throws {
        let start = t("2026-09-02T09:00")
        let now = t("2026-09-15T09:00")
        let visit = try Ingest.recordLiveVisit(
            LiveVisit(latitude: 1, longitude: 2, accuracyMeters: 10, arrival: start, departure: nil),
            now: start, to: db
        )
        try Ingest.apply(ContactChangeSet(token: Data([1])), now: start, expectedToken: nil, to: db)
        try Ingest.addExact(contactID: "keep", name: "Keep", at: start, placeID: visit.placeID, to: db)
        try Ingest.setNote(contactID: "keep", note: "Keep this note", to: db)
        let before = try db.reader.read { db in
            (try Meet.fetchOne(db, key: "keep"), try PendingNotice.fetchOne(db, key: "keep"),
             try Visit.fetchAll(db), try Place.fetchAll(db))
        }
        let summary = try Ingest.apply(
            ContactChangeSet(added: [
                ContactSnapshot(contactID: "keep", name: "Renamed"),
                ContactSnapshot(contactID: "new", name: "New"),
            ], token: Data([2]), isSnapshot: true),
            now: now, expectedToken: Data([1]), useLocationEvidence: false, to: db
        )
        #expect(summary.newPeople == 1)
        try db.reader.read { (db: Database) throws -> Void in
            let meet = try #require(try Meet.fetchOne(db, key: "new"))
            #expect(meet.tier == .dateOnly)
            #expect(meet.placeID == nil)
            #expect(meet.addSeenStart == start)
            #expect(meet.addSeenEnd == now)
            #expect(!meet.isConfirmed)
            #expect(try Meet.fetchOne(db, key: "keep") == before.0)
            #expect(try Person.fetchOne(db, key: "keep")?.note == "Keep this note")
            #expect(try PendingNotice.fetchOne(db, key: "keep") == before.1)
            #expect(try PendingNotice.fetchOne(db, key: "new") != nil)
            #expect(try Visit.fetchAll(db) == before.2)
            #expect(try Place.fetchAll(db) == before.3)
            #expect(try db.value(for: .contactsHistoryToken) == Data([2]))
            #expect(try db.date(for: .lastTick) == now)
        }
    }
}
