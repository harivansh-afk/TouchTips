// Google Maps Timeline export, as produced on-device by the Maps app.
// iOS writes a bare array of segments; Android wraps them in `semanticSegments`. Field spellings differ.

import Foundation
import GRDB

public enum TimelineExport {
    public struct VisitSegment: Hashable, Sendable {
        public var start: Date
        public var end: Date
        public var placeID: String?
        public var latitude: Double
        public var longitude: Double
    }

    public enum DecodeError: Error, Sendable {
        case unrecognizedShape
    }

    /// Visit segments only. Activities and raw paths are ignored.
    public static func decode(_ data: Data) throws -> [VisitSegment] {
        let decoder = JSONDecoder()
        let segments: [Segment]
        if let list = try? decoder.decode([Segment].self, from: data) {
            segments = list
        } else if let wrapped = try? decoder.decode(Wrapper.self, from: data) {
            segments = wrapped.semanticSegments
        } else {
            throw DecodeError.unrecognizedShape
        }

        let dates = ISO8601Dates()
        return segments.compactMap { segment in
            guard let candidate = segment.visit?.topCandidate, let coordinate = candidate.coordinate,
                  let start = dates.parse(segment.startTime), let end = dates.parse(segment.endTime),
                  end >= start else { return nil }
            return VisitSegment(
                start: start, end: end, placeID: candidate.placeID,
                latitude: coordinate.latitude, longitude: coordinate.longitude
            )
        }
    }

    // MARK: - Wire format

    private struct Wrapper: Decodable {
        var semanticSegments: [Segment]
    }

    private struct Segment: Decodable {
        var startTime: String
        var endTime: String
        var visit: VisitBody?
    }

    private struct VisitBody: Decodable {
        var topCandidate: Candidate?
    }

    private struct Candidate: Decodable {
        var placeID: String?
        var coordinate: Coordinate?

        private enum Keys: String, CodingKey {
            case placeID
            case placeId
            case placeLocation
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            placeID = try container.decodeIfPresent(String.self, forKey: .placeID)
                ?? container.decodeIfPresent(String.self, forKey: .placeId)
            if let text = try? container.decode(String.self, forKey: .placeLocation) {
                coordinate = Coordinate(text)
            } else if let object = try? container.decode(LatLng.self, forKey: .placeLocation) {
                coordinate = Coordinate(object.latLng)
            }
        }
    }

    private struct LatLng: Decodable {
        var latLng: String
    }

    struct Coordinate: Hashable {
        var latitude: Double
        var longitude: Double

        /// Accepts `geo:37.77,-122.41` and `37.77°, -122.41°`.
        init?(_ text: String) {
            let body = text.hasPrefix("geo:") ? String(text.dropFirst(4)) : text
            let parts = body
                .replacingOccurrences(of: "°", with: "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]),
                  (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
            latitude = lat
            longitude = lon
        }
    }

    private struct ISO8601Dates {
        private let fractional: ISO8601DateFormatter
        private let whole: ISO8601DateFormatter

        init() {
            fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            whole = ISO8601DateFormatter()
            whole.formatOptions = [.withInternetDateTime]
        }

        func parse(_ text: String) -> Date? {
            fractional.date(from: text) ?? whole.date(from: text)
        }
    }
}

public enum TimelineImporter {
    public struct Summary: Hashable, Sendable {
        public var visitsAdded = 0
        public var placesAdded = 0
        public var first: Date?
        public var last: Date?
    }

    /// Idempotent: re-importing the same file adds nothing.
    public static func importVisits(_ segments: [TimelineExport.VisitSegment], into database: AppDatabase) throws -> Summary {
        try database.writer.write { db in
            var summary = Summary()
            var placeIDs: [String: Int64] = [:]

            for segment in segments {
                let key = segment.placeID.map(PlaceKey.google) ?? PlaceKey.cell(latitude: segment.latitude, longitude: segment.longitude)
                let placeID: Int64
                if let known = placeIDs[key] {
                    placeID = known
                } else {
                    let existed = try Place.filter(Place.Columns.key == key).isEmpty(db) == false
                    let place = try Place.findOrCreate(db, key: key, latitude: segment.latitude, longitude: segment.longitude)
                    placeID = place.id!
                    placeIDs[key] = placeID
                    if !existed { summary.placesAdded += 1 }
                }

                var visit = Visit(placeID: placeID, start: segment.start, end: segment.end, source: .timeline)
                try visit.insert(db, onConflict: .ignore)
                if db.changesCount > 0 {
                    summary.visitsAdded += 1
                    summary.first = min(summary.first ?? segment.start, segment.start)
                    summary.last = max(summary.last ?? segment.end, segment.end)
                }
            }
            return summary
        }
    }
}
