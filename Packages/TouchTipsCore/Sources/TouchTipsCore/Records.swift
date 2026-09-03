// The five things touchtips stores. Plain values, no framework types.
// GRDB conformances live in Records+GRDB.swift so this file stays framework-free.

import Foundation

/// How sure we are about a meeting. Lower is better.
public enum Tier: Int, Codable, Hashable, Sendable, Comparable {
    /// Added from the app, or set by the user.
    case exact = 0
    /// A visit contained the moment the contact appeared.
    case witnessed = 1
    /// The nearest visit was within `Resolver.window`.
    case inferred = 2
    /// We know roughly when, not where.
    case dateOnly = 3

    public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// How finely `Meet.start` should be read.
public enum Precision: String, Codable, Hashable, Sendable {
    case exact, day, month, year

    /// The coarsest unit that still describes an interval honestly.
    public static func spanning(_ start: Date, _ end: Date) -> Precision {
        let span = end.timeIntervalSince(start)
        if span <= 36 * 3600 { return .day }
        if span <= 45 * 86400 { return .month }
        return .year
    }
}

public enum VisitSource: String, Codable, Hashable, Sendable {
    case timeline
    case live
}

/// One contact, keyed by `CNContact.identifier`.
public struct Person: Codable, Hashable, Identifiable, Sendable {
    public var contactID: String
    public var name: String
    /// Existed before the first run. No meeting can be inferred for these.
    public var beforeInstall: Bool
    public var createdAt: Date

    public var id: String { contactID }

    public init(contactID: String, name: String, beforeInstall: Bool, createdAt: Date) {
        self.contactID = contactID
        self.name = name
        self.beforeInstall = beforeInstall
        self.createdAt = createdAt
    }

    public var initials: String { Person.initials(for: name) }

    public static func initials(for name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        let picks = words.count > 1 ? [words[0], words[words.count - 1]] : Array(words.prefix(1))
        let letters = String(picks.compactMap(\.first)).uppercased()
        return letters.isEmpty ? "?" : letters
    }
}

/// A distinct location. `key` dedupes: a Google place ID when we have one, else a ~110 m cell.
public struct Place: Codable, Hashable, Identifiable, Sendable {
    public var id: Int64?
    public var key: String
    public var latitude: Double
    public var longitude: Double
    public var name: String?
    /// Set when geocoding was attempted, whether or not it produced a name.
    public var namedAt: Date?

    public init(id: Int64? = nil, key: String, latitude: Double, longitude: Double, name: String? = nil, namedAt: Date? = nil) {
        self.id = id
        self.key = key
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
        self.namedAt = namedAt
    }
}

public enum PlaceKey {
    public static func google(_ placeID: String) -> String { "g:" + placeID }

    /// Three decimals is about 110 m. Two visits to one café share a cell; two cafés a block apart usually do not.
    public static func cell(latitude: Double, longitude: Double) -> String {
        "c:" + String(format: "%.3f,%.3f", latitude, longitude)
    }
}

/// A stay at a place. `end == .distantFuture` means still there.
public struct Visit: Codable, Hashable, Identifiable, Sendable {
    public var id: Int64?
    public var placeID: Int64
    public var start: Date
    public var end: Date
    public var source: VisitSource
    public var accuracyMeters: Double?

    public init(id: Int64? = nil, placeID: Int64, start: Date, end: Date, source: VisitSource, accuracyMeters: Double? = nil) {
        self.id = id
        self.placeID = placeID
        self.start = start
        self.end = end
        self.source = source
        self.accuracyMeters = accuracyMeters
    }

    public var isOngoing: Bool { end == .distantFuture }
}

/// Our best answer for one person. Recomputed unless `userSet`.
public struct Meet: Codable, Hashable, Identifiable, Sendable {
    public var contactID: String
    public var start: Date
    public var end: Date
    public var precision: Precision
    public var placeID: Int64?
    public var tier: Tier
    public var userSet: Bool
    /// The window in which the contact appeared, kept so a later visit can upgrade the answer.
    public var addSeenStart: Date?
    public var addSeenEnd: Date?
    public var computedAt: Date

    public var id: String { contactID }

    public init(
        contactID: String, start: Date, end: Date, precision: Precision, placeID: Int64?, tier: Tier,
        userSet: Bool, addSeenStart: Date?, addSeenEnd: Date?, computedAt: Date
    ) {
        self.contactID = contactID
        self.start = start
        self.end = end
        self.precision = precision
        self.placeID = placeID
        self.tier = tier
        self.userSet = userSet
        self.addSeenStart = addSeenStart
        self.addSeenEnd = addSeenEnd
        self.computedAt = computedAt
    }
}

/// Cursors and small state the data layer owns.
public struct KeyValue: Codable, Hashable, Sendable {
    public var key: String
    public var value: Data

    public init(key: String, value: Data) {
        self.key = key
        self.value = value
    }
}

public enum StoreKey: String, Sendable {
    /// Opaque `CNChangeHistoryFetchRequest` token. Absent means the contact store was never read.
    case contactsHistoryToken
    /// When the last contacts diff ran. Adds seen next tick appeared after this.
    case lastTick
}
