import Foundation
import TouchedTipsCore

struct PeopleSection: Identifiable, Hashable {
    let id: String
    let title: String
    /// Under the title, when the section is a place: how many people, over which years.
    var subtitle: String?
    /// The place this section is, so the heading can show it on the map.
    var placeID: Int64?
    var rows: [PersonRow]
}

/// Dated people grouped by month, newest first, and the undated ones kept apart.
struct PeopleGroups: Hashable {
    var sections: [PeopleSection] = []
    /// Saved before TouchedTips, alphabetical. Shown as one row that pushes its own list.
    var undocumented: [PersonRow] = []
}

/// One line of the timeline: a month on the spine, a stretch with nobody in it, or a person.
enum TimelineItem: Identifiable, Hashable {
    case month(id: String, title: String)
    case quiet(id: String, days: Int)
    case person(PersonRow)

    var id: String {
        switch self {
        case let .month(id, _), let .quiet(id, _): id
        case let .person(row): row.id
        }
    }
}

enum PeopleSections {
    static func make(from rows: [PersonRow], matching query: String = "", calendar: Calendar = .current) -> PeopleGroups {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let visible = trimmed.isEmpty ? rows : rows.filter { row in
            row.person.name.localizedCaseInsensitiveContains(trimmed)
                || (row.place?.name?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }

        let dated = visible
            .compactMap { row in row.meet.map { (row: row, start: $0.start) } }
            .sorted { $0.start > $1.start }
        let undated = visible
            .filter { $0.meet == nil }
            .sorted { $0.person.name.localizedStandardCompare($1.person.name) == .orderedAscending }

        var sections: [PeopleSection] = []
        for entry in dated {
            let monthStart = calendar.dateInterval(of: .month, for: entry.start)?.start ?? entry.start
            let id = monthStart.formatted(.iso8601.year().month())
            if sections.last?.id == id {
                sections[sections.count - 1].rows.append(entry.row)
            } else {
                sections.append(PeopleSection(id: id, title: Format.month(monthStart), rows: [entry.row]))
            }
        }
        return PeopleGroups(sections: sections, undocumented: undated)
    }

    /// Dated people by place, the place with the newest meeting first and newest first within it,
    /// then everyone with a date and no place. Undocumented people are not here; `make` has them.
    static func byPlace(from rows: [PersonRow]) -> [PeopleSection] {
        let dated = rows
            .compactMap { row in row.meet.map { (row: row, start: $0.start) } }
            .sorted { $0.start > $1.start }

        var sections: [PeopleSection] = []
        var index: [Int64: Int] = [:]
        var dateOnly: [PersonRow] = []
        for entry in dated {
            guard let place = entry.row.place, let placeID = place.id else {
                dateOnly.append(entry.row)
                continue
            }
            if let at = index[placeID] {
                sections[at].rows.append(entry.row)
            } else {
                index[placeID] = sections.count
                sections.append(PeopleSection(
                    id: "place-\(placeID)",
                    title: place.name ?? Format.coordinates(place.latitude, place.longitude),
                    placeID: placeID,
                    rows: [entry.row]
                ))
            }
        }
        for at in sections.indices {
            let starts = sections[at].rows.compactMap { $0.meet?.start }
            if let first = starts.min(), let last = starts.max() {
                sections[at].subtitle = "\(Format.peopleCount(starts.count)) · \(Format.yearSpan(first, last))"
            }
        }
        if !dateOnly.isEmpty {
            sections.append(PeopleSection(
                id: "date-only", title: "Date only", subtitle: Format.peopleCount(dateOnly.count), rows: dateOnly
            ))
        }
        return sections
    }

    /// A gap is named once it is longer than a week.
    static let quietAfterDays = 7

    /// The month sections as one line: a tick per month, a named gap wherever more than a week
    /// passed between two people, and the people in between. Newest at the top, like the sections.
    static func timeline(from sections: [PeopleSection], calendar: Calendar = .current) -> [TimelineItem] {
        var items: [TimelineItem] = []
        var previous: Date?
        for section in sections {
            items.append(.month(id: section.id, title: section.title))
            for row in section.rows {
                guard let start = row.meet?.start else { continue }
                if let previous,
                   let days = calendar.dateComponents(
                       [.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: previous)
                   ).day,
                   days > quietAfterDays {
                    items.append(.quiet(id: "quiet-\(row.id)", days: days))
                }
                items.append(.person(row))
                previous = start
            }
        }
        return items
    }
}
