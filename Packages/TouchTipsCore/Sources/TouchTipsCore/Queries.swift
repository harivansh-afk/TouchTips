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

public extension Place {
    /// Places people were met at, most recent meeting first. One-tap suggestions when choosing a place.
    static func recentlyMet(limit: Int) -> SQLRequest<Place> {
        """
        SELECT place.* FROM place
        JOIN meet ON meet.placeID = place.id
        GROUP BY place.id
        ORDER BY MAX(meet.start) DESC
        LIMIT \(limit)
        """
    }
}
