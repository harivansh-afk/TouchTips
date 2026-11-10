import Foundation
import GRDB
import Testing
@testable import TouchTipsCore

struct CloudSnapshotTests {
    @Test func carriesPeoplePlacesAndMeetsInTheServerShape() throws {
        let db = try AppDatabase.inMemory()
        try Ingest.apply(ContactChangeSet(token: Data([1])), now: t("2026-09-01T09:00"), to: db)
        try Ingest.apply(
            ContactChangeSet(added: [ContactSnapshot(contactID: "a", name: "Alice")], token: Data([2])),
            now: t("2026-09-02T12:00"), to: db
        )
        let place = try db.writer.write { try Place.findOrCreate($0, key: "cafe", latitude: 1, longitude: 2, name: "Cafe") }
        try Ingest.setUserMeetPlace(contactID: "a", placeID: place.id, now: t("2026-09-02T12:00"), to: db)

        let snapshot = try db.reader.read {
            try CloudSnapshot.build($0, now: t("2026-09-03T00:00"), timeZone: TimeZone(identifier: "Europe/Berlin")!)
        }
        #expect(snapshot.version == 1)
        #expect(snapshot.timeZone == "Europe/Berlin")
        #expect(snapshot.people.map(\.id) == ["a"])
        #expect(snapshot.places.map(\.name) == ["Cafe"])
        #expect(snapshot.meets.count == 1)
        #expect(snapshot.meets[0].personId == "a")
        #expect(snapshot.meets[0].placeId == place.id)
        #expect(snapshot.meets[0].placeConfirmed)
        #expect(!snapshot.meets[0].dateConfirmed)

        let json = try #require(String(data: snapshot.encoded(), encoding: .utf8))
        #expect(json.contains("\"generatedAt\":\"2026-09-03T00:00:00Z\""))
        #expect(json.contains("\"precision\":\"day\"") || json.contains("\"precision\":\"exact\""))
        #expect(json.contains("\"tier\":"))
    }
}
