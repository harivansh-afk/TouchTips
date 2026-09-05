// Read requests the app observes. Sorting and grouping happen in Swift; the sets are small.

import Foundation
import GRDB

/// A person with their answer and its place, if any.
public struct PersonRow: Decodable, FetchableRecord, Hashable, Identifiable, Sendable {
    public var person: Person
    public var meet: Meet?
    public var place: Place?

    public var id: String {
        person.contactID
    }

    public init(person: Person, meet: Meet?, place: Place?) {
        self.person = person
        self.meet = meet
        self.place = place
    }
}

public extension Person {
    static func rows() -> QueryInterfaceRequest<PersonRow> {
        Person
            .including(optional: Person.meet)
            .including(optional: Person.place)
            .asRequest(of: PersonRow.self)
    }

    static func row(contactID: String) -> QueryInterfaceRequest<PersonRow> {
        rows().filter(key: contactID)
    }

    static func rows(atPlace placeID: Int64) -> QueryInterfaceRequest<PersonRow> {
        rows(atPlaces: [placeID])
    }

    /// Everyone met at any of these places. The map asks for this when pins have merged.
    static func rows(atPlaces placeIDs: [Int64]) -> QueryInterfaceRequest<PersonRow> {
        Person
            .including(required: Person.meet.filter(placeIDs.contains(Meet.Columns.placeID)))
            .including(optional: Person.place)
            .asRequest(of: PersonRow.self)
    }
}

/// A place with how many people were met there. Drives the map.
public struct PlaceSummary: Decodable, FetchableRecord, Hashable, Identifiable, Sendable {
    public var id: Int64
    public var key: String
    public var latitude: Double
    public var longitude: Double
    public var name: String?
    public var people: Int
    /// At least one meeting here has been confirmed by the user.
    public var witnessed: Bool
    public var first: Date
    public var last: Date
    /// The one person met here, when there is exactly one. The map draws them instead of a count.
    public var soleContactID: String?
    public var soleName: String?

    public static func all() -> SQLRequest<PlaceSummary> {
        """
        SELECT place.id, place.key, place.latitude, place.longitude, place.name,
               COUNT(meet.contactID) AS people,
               MAX(meet.dateConfirmed AND meet.placeConfirmed) AS witnessed,
               MIN(meet.start) AS first,
               MAX(meet.start) AS last,
               CASE WHEN COUNT(meet.contactID) = 1 THEN MIN(meet.contactID) END AS soleContactID,
               CASE WHEN COUNT(meet.contactID) = 1 THEN MIN(person.name) END AS soleName
        FROM place
        JOIN meet ON meet.placeID = place.id
        LEFT JOIN person ON person.contactID = meet.contactID
        GROUP BY place.id
        """
    }
}

public extension Visit {
    /// Visits touching `[start, end]`.
    static func overlapping(_ start: Date, _ end: Date) -> QueryInterfaceRequest<Visit> {
        Visit.filter(Columns.start <= end && Columns.end >= start)
    }

    /// The visit that produced a witnessed or inferred meeting, for the evidence list.
    static func evidence(for meet: Meet) -> QueryInterfaceRequest<Visit>? {
        guard let placeID = meet.placeID, let seenStart = meet.addSeenStart,
              let seenEnd = meet.addSeenEnd else { return nil }
        let start = seenStart.addingTimeInterval(-Resolver.window)
        let end = seenEnd.addingTimeInterval(Resolver.window)
        return Visit
            .filter(Columns.placeID == placeID)
            .filter(Columns.start <= end && Columns.end >= start)
            .order(Columns.start)
            .limit(1)
    }
}

public extension Place {
    /// Places with at least one visit touching `[start, end]`. Suggestions for the Fix sheet.
    static func visited(between start: Date, and end: Date) -> QueryInterfaceRequest<Place> {
        Place
            .joining(required: Place.visits.filter(Visit.Columns.start <= end && Visit.Columns.end >= start))
            .distinct()
    }

    /// Places someone was met at that have not been geocoded yet.
    static func awaitingName(limit: Int) -> QueryInterfaceRequest<Place> {
        Place
            .filter(Columns.name == nil && Columns.namedAt == nil)
            .joining(required: Place.meets)
            .distinct()
            .order(Columns.id.desc)
            .limit(limit)
    }

    /// Places that appear on the map.
    static func withMeets() -> QueryInterfaceRequest<Place> {
        Place.joining(required: Place.meets).distinct()
    }
}
