import Foundation
import TouchTipsCore

struct PeopleSection: Identifiable, Hashable {
    let id: String
    let title: String
    var rows: [PersonRow]
}

enum PeopleSections {
    /// Newest month first, then everyone we have no date for.
    static func make(from rows: [PersonRow], matching query: String = "", calendar: Calendar = .current) -> [PeopleSection] {
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
        if !undated.isEmpty {
            sections.append(PeopleSection(id: "before-install", title: "Undocumented", rows: undated))
        }
        return sections
    }
}
