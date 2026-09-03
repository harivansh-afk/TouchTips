import Foundation
import TouchedTipsCore

struct PeopleSection: Identifiable, Hashable {
    let id: String
    let title: String
    var rows: [PersonRow]
}

/// Dated people grouped by month, newest first, and the undated ones kept apart.
struct PeopleGroups: Hashable {
    var sections: [PeopleSection] = []
    /// Saved before TouchedTips, alphabetical. Shown as one row that pushes its own list.
    var undocumented: [PersonRow] = []
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
}
