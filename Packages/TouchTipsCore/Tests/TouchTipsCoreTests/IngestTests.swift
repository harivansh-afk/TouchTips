import Foundation
import GRDB
import Testing
@testable import TouchTipsCore

@Suite struct IngestTests {
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

    @Test func aLaterAddIsResolvedAgainstVisits() throws {
        try Ingest.apply(ContactChangeSet(added: [snapshot("old")], token: Data([1])), now: t("2026-09-02T09:38"), to: db)
        try Ingest.recordLiveVisit(
            LiveVisit(latitude: 37.7764, longitude: -122.4231, accuracyMeters: 30, arrival: t("2026-09-02T10:12"), departure: t("2026-09-02T11:40")),
            now: t("2026-09-02T11:40"), to: db
        )

        let summary = try Ingest.apply(ContactChangeSet(added: [snapshot("new", "Dev Patel")], token: Data([2])), now: t("2026-09-02T11:41"), to: db)
        #expect(summary.newPeople == 1)

        let row = try db.reader.read { try Person.row(contactID: "new").fetchOne($0) }
        let meet = try #require(row?.meet)
        #expect(meet.tier == .witnessed)
        #expect(meet.addSeenStart == t("2026-09-02T09:38"))
        #expect(meet.addSeenEnd == t("2026-09-02T11:41"))
        #expect(meet.start == t("2026-09-02T10:12"))
        #expect(meet.end == t("2026-09-02T11:40"))
        #expect(row?.place?.key == PlaceKey.cell(latitude: 37.7764, longitude: -122.4231))
        #expect(row?.person.beforeInstall == false)
    }

    @Test func aVisitArrivingAfterTheAddUpgradesTheMeet() throws {
        try Ingest.apply(ContactChangeSet(added: [], token: Data([1])), now: t("2026-09-02T09:38"), to: db)
        try Ingest.apply(ContactChangeSet(added: [snapshot("new")], token: Data([2])), now: t("2026-09-02T11:41"), to: db)
        #expect(try db.reader.read { try Meet.fetchOne($0, key: "new")?.tier } == .dateOnly)

        try Ingest.recordLiveVisit(
            LiveVisit(latitude: 37.7764, longitude: -122.4231, accuracyMeters: 30, arrival: t("2026-09-02T10:12"), departure: t("2026-09-02T11:40")),
            now: t("2026-09-02T11:42"), to: db
        )
        let meet = try #require(try db.reader.read { try Meet.fetchOne($0, key: "new") })
        #expect(meet.tier == .witnessed)
        #expect(meet.placeID != nil)
    }

    @Test func anOngoingVisitIsExtendedNotDuplicated() throws {
        let arrival = t("2026-09-02T10:12")
        let first = try Ingest.recordLiveVisit(
            LiveVisit(latitude: 1, longitude: 2, accuracyMeters: 10, arrival: arrival, departure: nil), now: arrival, to: db
        )
        #expect(first.isOngoing)
        let second = try Ingest.recordLiveVisit(
            LiveVisit(latitude: 1, longitude: 2, accuracyMeters: 10, arrival: arrival, departure: t("2026-09-02T11:00")),
            now: t("2026-09-02T11:00"), to: db
        )
        #expect(second.id == first.id)
        #expect(try db.reader.read { try Visit.fetchCount($0) } == 1)
        #expect(second.end == t("2026-09-02T11:00"))
    }

    @Test func userAnswersAreNeverRecomputed() throws {
        try Ingest.apply(ContactChangeSet(added: [], token: Data([1])), now: t("2026-09-02T09:38"), to: db)
        try Ingest.apply(ContactChangeSet(added: [snapshot("new")], token: Data([2])), now: t("2026-09-02T11:41"), to: db)
        try Ingest.setUserMeet(
            contactID: "new", start: t("2025-03-01T00:00"), end: t("2025-03-31T23:59"), precision: .month, placeID: nil,
            now: t("2026-09-02T12:00"), to: db
        )
        try Ingest.recordLiveVisit(
            LiveVisit(latitude: 1, longitude: 2, accuracyMeters: 10, arrival: t("2026-09-02T10:12"), departure: t("2026-09-02T11:40")),
            now: t("2026-09-02T12:01"), to: db
        )
        let meet = try #require(try db.reader.read { try Meet.fetchOne($0, key: "new") })
        #expect(meet.userSet)
        #expect(meet.tier == .exact)
        #expect(meet.precision == .month)
        #expect(meet.addSeenStart == t("2026-09-02T09:38"))
    }

    @Test func deletingAContactRemovesItsMeet() throws {
        try Ingest.apply(ContactChangeSet(added: [], token: Data([1])), now: t("2026-09-02T09:38"), to: db)
        try Ingest.apply(ContactChangeSet(added: [snapshot("new")], token: Data([2])), now: t("2026-09-02T11:41"), to: db)
        let summary = try Ingest.apply(ContactChangeSet(deletedIDs: ["new"], token: Data([3])), now: t("2026-09-02T12:00"), to: db)
        #expect(summary.deleted == 1)
        #expect(try db.reader.read { try Meet.fetchCount($0) } == 0)
    }

    @Test func aHistoryResetOnlyAddsUnknownPeople() throws {
        try Ingest.apply(ContactChangeSet(added: [snapshot("a")], token: Data([1])), now: t("2026-09-02T09:38"), to: db)
        // Contacts dropped history: it re-sends everyone. Only "b" is actually new.
        let summary = try Ingest.apply(ContactChangeSet(added: [snapshot("a"), snapshot("b")], token: Data([2])), now: t("2026-09-02T11:41"), to: db)
        #expect(summary.newPeople == 1)
        #expect(try db.reader.read { try Person.fetchCount($0) } == 2)
        #expect(try db.reader.read { try Meet.fetchOne($0, key: "a") } == nil)
        #expect(try db.reader.read { try Meet.fetchOne($0, key: "b")?.tier } == .dateOnly)
    }

    @Test func placeSummaryCountsPeoplePerPlace() throws {
        try Ingest.apply(ContactChangeSet(added: [], token: Data([1])), now: t("2026-09-02T09:38"), to: db)
        try Ingest.recordLiveVisit(
            LiveVisit(latitude: 1, longitude: 2, accuracyMeters: 10, arrival: t("2026-09-02T10:00"), departure: t("2026-09-02T12:00")),
            now: t("2026-09-02T12:00"), to: db
        )
        try Ingest.apply(ContactChangeSet(added: [snapshot("x"), snapshot("y")], token: Data([2])), now: t("2026-09-02T11:00"), to: db)
        let summaries = try db.reader.read { try PlaceSummary.all().fetchAll($0) }
        #expect(summaries.count == 1)
        #expect(summaries.first?.people == 2)
        #expect(summaries.first?.witnessed == true)
    }
}
