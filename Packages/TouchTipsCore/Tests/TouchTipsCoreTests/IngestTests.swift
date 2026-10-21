import Foundation
import GRDB
import Testing
@testable import TouchTipsCore

struct IngestTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func snapshot(_ id: String, _ name: String = "Someone") -> ContactSnapshot {
        ContactSnapshot(contactID: id, name: name)
    }

    @Test func firstRunSnapshotsEveryoneAsBeforeInstall() throws {
        let summary = try Ingest.apply(
            ContactChangeSet(added: [snapshot("a"), snapshot("b")], token: Data([1])),
            now: t("2026-09-01T09:00"), to: db
        )
        #expect(summary.snapshotted == 2)
        #expect(summary.newPeople == 0)
        let rows = try db.reader.read { try Person.rows().fetchAll($0) }
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.person.beforeInstall && $0.meet == nil })
        #expect(try db.reader.read { try $0.value(for: .contactsHistoryToken) } == Data([1]))
    }

    @Test func aLaterAddIsADateOnlySuggestion() throws {
        try Ingest.apply(ContactChangeSet(added: [], token: Data([1])), now: t("2026-09-02T09:38"), to: db)
        let now = t("2026-09-02T14:14")
        let summary = try Ingest.apply(
            ContactChangeSet(added: [snapshot("new", "Alice Chen")], token: Data([2])),
            now: now,
            to: db
        )
        #expect(summary.added == ["new"])

        let row = try #require(try db.reader.read { try Person.row(contactID: "new").fetchOne($0) })
        let meet = try #require(row.meet)
        #expect(meet.tier == .dateOnly)
        #expect(meet.precision == .day)
        #expect(meet.start == t("2026-09-02T09:38"))
        #expect(meet.end == now)
        #expect(!meet.isConfirmed)
        #expect(row.place == nil)
        #expect(row.person.beforeInstall == false)
    }

    @Test func delayedDiscoveryRetainsTheLastSuccessfulReadAsLowerBound() throws {
        try Ingest.apply(ContactChangeSet(added: [], token: Data([1])), now: t("2026-09-02T09:00"), to: db)
        try Ingest.apply(
            ContactChangeSet(added: [snapshot("new")], token: Data([2])),
            now: t("2026-09-02T14:14"), to: db
        )
        let meet = try #require(try db.reader.read { try Meet.fetchOne($0, key: "new") })
        #expect(meet.addSeenStart == t("2026-09-02T09:00"))
        #expect(meet.addSeenEnd == t("2026-09-02T14:14"))
    }

    @Test func clockMovingBackwardsDoesNotInvertTheDiscoveryInterval() throws {
        try Ingest.apply(ContactChangeSet(added: [], token: Data([1])), now: t("2026-09-02T14:14"), to: db)
        try Ingest.apply(
            ContactChangeSet(added: [snapshot("new")], token: Data([2])),
            now: t("2026-09-02T09:00"), to: db
        )
        let meet = try #require(try db.reader.read { try Meet.fetchOne($0, key: "new") })
        #expect(meet.addSeenStart == t("2026-09-02T09:00"))
        #expect(meet.addSeenEnd == meet.addSeenStart)
    }

    @Test func confirmingKeepsTheAnswerAndMakesItTheUsers() throws {
        try Ingest.apply(ContactChangeSet(added: [], token: Data([1])), now: t("2026-09-02T09:38"), to: db)
        try Ingest.apply(
            ContactChangeSet(added: [snapshot("new")], token: Data([2])),
            now: t("2026-09-02T11:00"),
            to: db
        )
        let before = try #require(try db.reader.read { try Meet.fetchOne($0, key: "new") })
        try Ingest.confirmMeet(contactID: "new", now: t("2026-09-02T11:05"), to: db)
        let after = try #require(try db.reader.read { try Meet.fetchOne($0, key: "new") })
        #expect(after.userSet)
        #expect(after.tier == .exact)
        #expect(after.placeID == before.placeID)
        #expect(after.start == before.start)
    }

    @Test(arguments: [Precision.exact, .day, .month, .year])
    func changingOnlyPlacePreservesMeetingTimeAndPrecision(precision: Precision) throws {
        let start = t("2025-03-01T09:38")
        let end = precision == .exact ? start : t("2025-03-31T23:59")
        try Ingest.addExact(contactID: "a", name: "Alice", at: start, placeID: nil, to: db)
        try db.writer.write { db in
            var meet = try #require(try Meet.fetchOne(db, key: "a"))
            meet.end = end
            meet.precision = precision
            meet.userSet = false
            meet.dateConfirmed = false
            meet.placeConfirmed = false
            try meet.update(db)
        }
        let before = try #require(try db.reader.read { try Meet.fetchOne($0, key: "a") })
        let place = try db.writer.write { db in
            try Place.findOrCreate(db, key: "test-place", latitude: 1, longitude: 2, name: "Cafe")
        }
        try Ingest.setUserMeetPlace(contactID: "a", placeID: place.id, now: t("2026-09-02T12:00"), to: db)
        let after = try #require(try db.reader.read { try Meet.fetchOne($0, key: "a") })
        #expect(after.placeID == place.id)
        #expect(after.start == before.start)
        #expect(after.end == before.end)
        #expect(after.precision == before.precision)
        #expect(after.addSeenStart == before.addSeenStart)
        #expect(after.addSeenEnd == before.addSeenEnd)
        #expect(after.userSet)
        #expect(!after.dateConfirmed)
        #expect(after.placeConfirmed)
        #expect(!after.isConfirmed)

        try Ingest.setUserMeetPlace(contactID: "a", placeID: nil, now: t("2026-09-02T12:01"), to: db)
        let cleared = try #require(try db.reader.read { try Meet.fetchOne($0, key: "a") })
        #expect(cleared.placeID == nil)
        #expect(cleared.start == before.start)
        #expect(cleared.end == before.end)
        #expect(cleared.precision == before.precision)
    }

    @Test(arguments: [false, true])
    func reselectingTheCurrentPlaceDoesNotConfirmAnInferredMeeting(hasPlace: Bool) throws {
        try Ingest.apply(ContactChangeSet(added: [], token: Data([1])), now: t("2026-09-02T09:00"), to: db)
        try Ingest.apply(ContactChangeSet(added: [snapshot("a")], token: Data([2])), now: t("2026-09-02T12:00"), to: db)
        if hasPlace {
            try db.writer.write { db in
                let place = try Place.findOrCreate(db, key: "test-place", latitude: 1, longitude: 2, name: "Cafe")
                var meet = try #require(try Meet.fetchOne(db, key: "a"))
                meet.placeID = place.id
                try meet.update(db)
            }
        }
        let before = try #require(try db.reader.read { try Meet.fetchOne($0, key: "a") })
        #expect(!before.userSet)
        try Ingest.setUserMeetPlace(contactID: "a", placeID: before.placeID, now: t("2026-09-02T13:00"), to: db)
        let after = try #require(try db.reader.read { try Meet.fetchOne($0, key: "a") })
        #expect(after == before)
    }

    @Test func aPlaceAloneDoesNotInventAMeetingDate() throws {
        try Ingest.apply(ContactChangeSet(added: [snapshot("a")], token: Data([1])), now: t("2026-09-02T09:00"), to: db)
        let place = try db.writer.write { db in
            try Place.findOrCreate(db, key: "test-place", latitude: 1, longitude: 2, name: "Cafe")
        }
        try Ingest.setUserMeetPlace(contactID: "a", placeID: place.id, now: t("2026-09-02T12:00"), to: db)
        #expect(try db.reader.read { try Meet.fetchOne($0, key: "a") } == nil)
    }

    @Test func deletingAContactRemovesItsMeet() throws {
        try Ingest.apply(ContactChangeSet(added: [], token: Data([1])), now: t("2026-09-02T09:38"), to: db)
        try Ingest.apply(
            ContactChangeSet(added: [snapshot("new")], token: Data([2])),
            now: t("2026-09-02T11:41"),
            to: db
        )
        let summary = try Ingest.apply(
            ContactChangeSet(deletedIDs: ["new"], token: Data([3])),
            now: t("2026-09-02T12:00"),
            to: db
        )
        #expect(summary.deleted == 1)
        #expect(try db.reader.read { try Meet.fetchCount($0) } == 0)
    }

    @Test func aHistoryResetOnlyAddsUnknownPeople() throws {
        try Ingest.apply(ContactChangeSet(added: [snapshot("a")], token: Data([1])), now: t("2026-09-02T09:38"), to: db)
        // Contacts dropped history: it re-sends everyone. Only "b" is actually new.
        let summary = try Ingest.apply(
            ContactChangeSet(added: [snapshot("a"), snapshot("b")], token: Data([2])),
            now: t("2026-09-02T11:41"),
            to: db
        )
        #expect(summary.newPeople == 1)
        #expect(try db.reader.read { try Person.fetchCount($0) } == 2)
        #expect(try db.reader.read { try Meet.fetchOne($0, key: "a") } == nil)
        #expect(try db.reader.read { try Meet.fetchOne($0, key: "b")?.tier } == .dateOnly)
    }

    @Test func placeSummaryCountsPeoplePerPlace() throws {
        let cafe = Place(key: "cafe", latitude: 1, longitude: 2, name: "Cafe")
        try Ingest.addExact(contactID: "x", name: "X", at: t("2026-09-02T11:00"), place: cafe, to: db)
        try Ingest.addExact(contactID: "y", name: "Y", at: t("2026-09-02T11:00"), place: cafe, to: db)
        try db.writer.write { try Meet.updateAll($0, Meet.Columns.placeConfirmed.set(to: false)) }
        let summaries = try db.reader.read { try PlaceSummary.all().fetchAll($0) }
        #expect(summaries.count == 1)
        #expect(summaries.first?.people == 2)
        #expect(summaries.first?.witnessed == false)
        #expect(summaries.first?.soleContactID == nil)
    }

    @Test func placeSummaryNamesTheOnlyPersonMetThere() throws {
        let cafe = Place(key: "cafe", latitude: 1, longitude: 2, name: "Cafe")
        try Ingest.addExact(contactID: "x", name: "Dev Patel", at: t("2026-09-02T11:00"), place: cafe, to: db)
        let summary = try db.reader.read { try PlaceSummary.all().fetchOne($0) }
        #expect(summary?.people == 1)
        #expect(summary?.soleContactID == "x")
        #expect(summary?.soleName == "Dev Patel")
    }
}

struct NoteTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
        try Ingest.addExact(contactID: "a", name: "Alice", at: t("2026-09-01T09:00"), placeID: nil, to: db)
    }

    private func note() throws -> String? {
        try db.reader.read { try Person.fetchOne($0, key: "a")?.note }
    }

    @Test func aNoteIsSavedTrimmedAndClearedWhenBlank() throws {
        try Ingest.setNote(contactID: "a", note: "  runs a sailing school in Goa \n", to: db)
        #expect(try note() == "runs a sailing school in Goa")
        try Ingest.setNote(contactID: "a", note: "   ", to: db)
        #expect(try note() == nil)
    }

    @Test func aNameUpdateFromContactsKeepsTheNote() throws {
        try Ingest.setNote(contactID: "a", note: "sailing", to: db)
        _ = try Ingest.apply(
            ContactChangeSet(
                added: [],
                updated: [ContactSnapshot(contactID: "a", name: "Alice Chen")],
                token: Data([2])
            ),
            now: t("2026-09-02T09:00"), to: db
        )
        #expect(try note() == "sailing")
        #expect(try db.reader.read { try Person.fetchOne($0, key: "a")?.name } == "Alice Chen")
    }
}

struct RecentPlaceTests {
    @Test func recentlyMetPlacesAreOrderedByLatestMeetingAndDeduplicated() throws {
        let db = try AppDatabase.inMemory()
        let cafe = Place(key: "cafe", latitude: 1, longitude: 2, name: "Cafe")
        let park = Place(key: "park", latitude: 3, longitude: 4, name: "Park")
        try Ingest.addExact(contactID: "a", name: "A", at: t("2026-09-01T09:00"), place: cafe, to: db)
        try Ingest.addExact(contactID: "b", name: "B", at: t("2026-09-02T09:00"), place: park, to: db)
        try Ingest.addExact(contactID: "c", name: "C", at: t("2026-09-03T09:00"), place: cafe, to: db)
        try Ingest.addExact(contactID: "d", name: "D", at: t("2026-09-04T09:00"), place: nil, to: db)
        let recent = try db.reader.read { try Place.recentlyMet(limit: 5).fetchAll($0) }
        #expect(recent.map(\.key) == ["cafe", "park"])
        #expect(try db.reader.read { try Place.recentlyMet(limit: 1).fetchAll($0) }.map(\.key) == ["cafe"])
    }
}
