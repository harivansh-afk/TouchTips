// GRDB conformances, columns and associations for Records.swift.

import Foundation
import GRDB

extension Tier: DatabaseValueConvertible {}
extension Precision: DatabaseValueConvertible {}
extension VisitSource: DatabaseValueConvertible {}
extension WakeSource: DatabaseValueConvertible {}

extension Person: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "person"

    public enum Columns: String, ColumnExpression {
        case contactID, name, beforeInstall, createdAt
    }

    public static let meet = hasOne(Meet.self)
    public static let place = hasOne(Place.self, through: meet, using: Meet.place)
}

extension Place: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "place"

    public enum Columns: String, ColumnExpression {
        case id, key, latitude, longitude, name, namedAt
    }

    public static let visits = hasMany(Visit.self)
    public static let meets = hasMany(Meet.self)

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// Fetch by key or insert. A `name` passed here only fills an empty one.
    public static func findOrCreate(
        _ db: Database, key: String, latitude: Double, longitude: Double, name: String? = nil
    ) throws -> Place {
        if var existing = try Place.filter(Columns.key == key).fetchOne(db) {
            if existing.name == nil, let name {
                existing.name = name
                existing.namedAt = Date()
                try existing.update(db)
            }
            return existing
        }
        var place = Place(key: key, latitude: latitude, longitude: longitude, name: name, namedAt: name == nil ? nil : Date())
        try place.insert(db)
        return place
    }
}

extension Visit: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "visit"

    public enum Columns: String, ColumnExpression {
        case id, placeID, start, end, source, accuracyMeters
    }

    public static let place = belongsTo(Place.self)

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension Meet: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "meet"

    public enum Columns: String, ColumnExpression {
        case contactID, start, end, precision, placeID, tier, userSet, addSeenStart, addSeenEnd, computedAt
    }

    public static let person = belongsTo(Person.self)
    public static let place = belongsTo(Place.self)
}

extension KeyValue: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "kv"
}

extension Heartbeat: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "heartbeat"

    public enum Columns: String, ColumnExpression {
        case id, source, at, batteryLevel
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// Heartbeats at or after `start`, oldest first.
    public static func since(_ start: Date) -> QueryInterfaceRequest<Heartbeat> {
        Heartbeat.filter(Columns.at >= start).order(Columns.at)
    }
}

public extension Database {
    func value(for key: StoreKey) throws -> Data? {
        try KeyValue.fetchOne(self, key: key.rawValue)?.value
    }

    func setValue(_ data: Data?, for key: StoreKey) throws {
        if let data {
            try KeyValue(key: key.rawValue, value: data).save(self)
        } else {
            try KeyValue.deleteOne(self, key: key.rawValue)
        }
    }

    func date(for key: StoreKey) throws -> Date? {
        guard let data = try value(for: key), let text = String(data: data, encoding: .utf8),
              let seconds = TimeInterval(text) else { return nil }
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    func setDate(_ date: Date?, for key: StoreKey) throws {
        try setValue(date.map { Data(String($0.timeIntervalSinceReferenceDate).utf8) }, for: key)
    }
}
