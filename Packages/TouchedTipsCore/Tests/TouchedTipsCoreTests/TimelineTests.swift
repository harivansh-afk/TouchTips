import Foundation
import GRDB
import Testing
@testable import TouchedTipsCore

@Suite struct TimelineTests {
    static let iosExport = Data("""
    [
      {"startTime":"2024-05-01T09:12:00.000-07:00","endTime":"2024-05-01T10:40:00.000-07:00",
       "visit":{"hierarchyLevel":"0","probability":"0.640000",
                "topCandidate":{"placeID":"ChIJabc","semanticType":"Unknown","probability":"0.5","placeLocation":"geo:37.776400,-122.423100"}}},
      {"startTime":"2024-05-01T10:40:00.000-07:00","endTime":"2024-05-01T11:00:00.000-07:00",
       "activity":{"distanceMeters":"1200.0","topCandidate":{"type":"WALKING","probability":"0.9"}}},
      {"startTime":"2024-05-02T08:00:00.000-07:00","endTime":"2024-05-02T09:00:00.000-07:00",
       "visit":{"topCandidate":{"placeLocation":"geo:38.033500,-78.508100"}}}
    ]
    """.utf8)

    static let androidExport = Data("""
    {"semanticSegments":[
      {"startTime":"2024-05-01T09:12:00.000Z","endTime":"2024-05-01T10:40:00.000Z",
       "visit":{"topCandidate":{"placeId":"ChIJabc","placeLocation":{"latLng":"37.7764°, -122.4231°"}}}}
    ],"rawSignals":[],"userLocationProfile":{}}
    """.utf8)

    @Test func decodesTheIOSBareArray() throws {
        let visits = try TimelineExport.decode(Self.iosExport)
        #expect(visits.count == 2)
        #expect(visits[0].placeID == "ChIJabc")
        #expect(visits[0].latitude == 37.7764)
        #expect(visits[0].longitude == -122.4231)
        #expect(visits[0].start == t("2024-05-01T16:12"))
        #expect(visits[1].placeID == nil)
    }

    @Test func decodesTheAndroidWrapper() throws {
        let visits = try TimelineExport.decode(Self.androidExport)
        #expect(visits.count == 1)
        #expect(visits[0].placeID == "ChIJabc")
        #expect(visits[0].latitude == 37.7764)
    }

    @Test func rejectsOtherJSON() {
        #expect(throws: TimelineExport.DecodeError.self) {
            try TimelineExport.decode(Data("{\"hello\":1}".utf8))
        }
    }

    @Test func parsesBothCoordinateSpellings() {
        #expect(TimelineExport.Coordinate("geo:1.5,-2.25")?.longitude == -2.25)
        #expect(TimelineExport.Coordinate("1.5°, -2.25°")?.latitude == 1.5)
        #expect(TimelineExport.Coordinate("nonsense") == nil)
        #expect(TimelineExport.Coordinate("geo:91,0") == nil)
    }

    @Test func importIsIdempotent() throws {
        let db = try AppDatabase.inMemory()
        let visits = try TimelineExport.decode(Self.iosExport)
        let first = try TimelineImporter.importVisits(visits, into: db)
        #expect(first.visitsAdded == 2)
        #expect(first.placesAdded == 2)
        #expect(first.first == t("2024-05-01T16:12"))
        let second = try TimelineImporter.importVisits(visits, into: db)
        #expect(second.visitsAdded == 0)
        #expect(second.placesAdded == 0)
        #expect(try db.reader.read { try Visit.fetchCount($0) } == 2)
        let googlePlaces = try db.reader.read { db in
            try Place.filter(Place.Columns.key == PlaceKey.google("ChIJabc")).fetchCount(db)
        }
        #expect(googlePlaces == 1)
    }
}
