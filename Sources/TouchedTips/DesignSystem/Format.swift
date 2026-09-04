import Foundation
import TouchedTipsCore

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

    /// "Saturday"
    static func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide))
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    /// "40 m" or "1.2 km"
    static func distance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
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
        case .exact, .day: (weekday(meet.start), longDate(meet.start))
        case .month: ("Sometime in", month(meet.start))
        case .year: ("Sometime in", meet.start.formatted(.dateTime.year()))
        }
    }

    static func placeName(_ row: PersonRow) -> String? {
        guard let place = row.place else { return nil }
        return place.name ?? coordinates(place.latitude, place.longitude)
    }

    /// Second line of a people row. Empty for someone with no date, since their list already says so.
    static func rowSubtitle(_ row: PersonRow) -> String {
        if let name = placeName(row) { return name }
        return row.meet == nil ? "" : "Date only"
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

    /// "Sat 8 Aug 2026", or as much of it as was known. The second line of a row whose place is the heading.
    static func dateLine(_ meet: Meet) -> String {
        switch meet.precision {
        case .exact, .day: meet.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
        case .month: month(meet.start)
        case .year: meet.start.formatted(.dateTime.year())
        }
    }

    /// "1 person" or "4 people"
    static func peopleCount(_ count: Int) -> String {
        count == 1 ? "1 person" : "\(count) people"
    }

    /// "Twelve quiet days", "Three quiet months", "A quiet year". Words, because it is set in the serif.
    static func quiet(days: Int) -> String {
        let (count, unit) = days < 60 ? (days, "day") : days < 365 ? (days / 30, "month") : (days / 365, "year")
        let number = count == 1 ? "A" : spelled(count)
        return "\(number) quiet \(unit)\(count == 1 ? "" : "s")"
    }

    /// "Twelve". Digits from a hundred up, where the words stop reading at a glance.
    private static func spelled(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        guard count < 100, let words = formatter.string(from: NSNumber(value: count)) else { return String(count) }
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
