// What the phone sends to the cloud: everything TouchTips itself shows, nothing Contacts owns.
// Mirrors the server's SnapshotSchema. Dates go out as ISO 8601.

import Foundation
import GRDB

public struct CloudSnapshot: Codable, Equatable, Sendable {
    public struct Person: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var note: String?
        public var createdAt: Date
    }

    public struct Place: Codable, Equatable, Sendable {
        public var id: Int64
        public var name: String?
        public var latitude: Double
        public var longitude: Double
    }

    public struct Meet: Codable, Equatable, Sendable {
        public var personId: String
        public var start: Date
        public var end: Date
        public var precision: Precision
        public var tier: Int
        public var placeId: Int64?
        public var userSet: Bool
        public var dateConfirmed: Bool
        public var placeConfirmed: Bool
    }

    public var version = 1
    public var generatedAt: Date
    public var timeZone: String
    public var people: [Person]
    public var places: [Place]
    public var meets: [Meet]

    /// Everything in the database, in one read.
    public static func build(_ db: Database, now: Date = Date(), timeZone: TimeZone = .current) throws -> CloudSnapshot {
        let people = try TouchTipsCore.Person.order(TouchTipsCore.Person.Columns.name).fetchAll(db).map {
            Person(id: $0.contactID, name: $0.name, note: $0.note, createdAt: $0.createdAt)
        }
        let places = try TouchTipsCore.Place.fetchAll(db).compactMap { place -> Place? in
            guard let id = place.id else { return nil }
            return Place(id: id, name: place.name, latitude: place.latitude, longitude: place.longitude)
        }
        let meets = try TouchTipsCore.Meet.fetchAll(db).map {
            Meet(
                personId: $0.contactID, start: $0.start, end: $0.end, precision: $0.precision, tier: $0.tier.rawValue,
                placeId: $0.placeID, userSet: $0.userSet, dateConfirmed: $0.dateConfirmed, placeConfirmed: $0.placeConfirmed
            )
        }
        return CloudSnapshot(generatedAt: now, timeZone: timeZone.identifier, people: people, places: places, meets: meets)
    }

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    public func encoded() throws -> Data {
        try Self.encoder.encode(self)
    }
}
