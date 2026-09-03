import Foundation
import TouchTipsCore

/// Every user-facing date and place string. Views never format on their own.
enum Format {
    static func month(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    /// "Tue 1"
    static func dayInMonth(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day())
    }

    /// "8 August 2026"
    static func longDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year())
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    static func coordinates(_ latitude: Double, _ longitude: Double) -> String {
        String(format: "%.3f, %.3f", latitude, longitude)
    }

    /// The trailing text on a people row. Empty for month precision because the section header already says it.
    static func rowDate(_ meet: Meet) -> String {
        switch meet.precision {
        case .exact, .day: dayInMonth(meet.start)
        case .month: ""
        case .year: meet.start.formatted(.dateTime.year())
        }
    }

    /// Serif lead line and bold body line for the hero card.
    static func headline(for meet: Meet) -> (lead: String, body: String) {
        switch meet.precision {
        case .exact, .day: (meet.start.formatted(.dateTime.weekday(.wide)), longDate(meet.start))
        case .month: ("Sometime in", month(meet.start))
        case .year: ("Sometime in", meet.start.formatted(.dateTime.year()))
        }
    }

    /// "Blue Bottle · between 10:41 and 11:02"
    static func placeAndWindow(_ row: PersonRow) -> String {
        [placeName(row), window(row.meet)].compactMap { $0 }.joined(separator: " · ")
    }

    static func placeName(_ row: PersonRow) -> String? {
        guard let place = row.place else { return nil }
        return place.name ?? coordinates(place.latitude, place.longitude)
    }

    /// Second line of a people row.
    static func rowSubtitle(_ row: PersonRow) -> String {
        if let name = placeName(row) { return name }
        return row.meet == nil ? "Before touchtips" : "Date only"
    }

    static func window(_ meet: Meet?) -> String? {
        guard let meet, meet.precision == .exact || meet.precision == .day else { return nil }
        if meet.precision == .exact { return time(meet.start) }
        guard meet.end > meet.start, Calendar.current.isDate(meet.start, inSameDayAs: meet.end) else { return nil }
        return "between \(time(meet.start)) and \(time(meet.end))"
    }

    static func visitSpan(_ visit: Visit) -> String {
        visit.isOngoing ? "since \(time(visit.start))" : "\(time(visit.start)) to \(time(visit.end))"
    }

    static func tierName(_ tier: Tier?) -> String {
        switch tier {
        case .exact: "exact"
        case .witnessed: "witnessed"
        case .inferred: "inferred"
        case .dateOnly: "date only"
        case nil: "no date"
        }
    }

    /// "2024 to 2026" or "2026"
    static func yearSpan(_ first: Date, _ last: Date) -> String {
        let a = first.formatted(.dateTime.year())
        let b = last.formatted(.dateTime.year())
        return a == b ? a : "\(a) to \(b)"
    }
}
