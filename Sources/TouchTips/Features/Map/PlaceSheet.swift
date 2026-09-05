import SwiftUI
import TouchTipsCore

/// Everyone met at one pin. One place is a list, newest first; several places, merged at this
/// zoom, are the same list under a heading per place, the place with the newest meeting first.
struct PlaceSheet: View {
    let group: PlaceGroup
    /// Called with a contact ID when a row is tapped. The map closes the sheet, then pushes.
    let onOpen: (String) -> Void

    @Environment(AppModel.self) private var app
    @State private var content: PlaceSheetContent?

    var body: some View {
        List {
            if let content {
                // The heading and rows describe the same live database snapshot.
                SwiftUI.Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(content.title)
                            .font(.display(26))
                            .lineLimit(2)
                        Text(content.subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listRowInsets(EdgeInsets(top: 18, leading: 20, bottom: 10, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                ForEach(content.sections) { section in
                    if content.sections.count > 1 {
                        SwiftUI.Section {
                            Text(section.title)
                                .font(.display(20))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 4, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    rows(section.rows)
                }
            } else {
                ProgressView("Loading place")
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .task(id: group) { await observe() }
    }

    /// The heading says where, so each row says when.
    private func rows(_ people: [PersonRow]) -> some View {
        let indexed = people.indexedRows()
        return ForEach(indexed) { entry in
            let row = entry.item
            Button {
                HapticManager.selection()
                onOpen(row.id)
            } label: {
                PersonRowView(row: row, showsPlace: false)
            }
            .buttonStyle(.press)
            .personListRow(showSeparator: entry.index < indexed.count - 1)
        }
    }

    private func observe() async {
        let places = group.places
        let observation = ValueObservation.tracking { db in
            try Person.rows(atPlaces: places.map(\.id)).fetchAll(db)
        }
        do {
            for try await value in observation.values(in: app.database.reader) {
                guard !Task.isCancelled else { return }
                let next = PlaceSheetContent(rows: value)
                if content != next {
                    content = next
                }
            }
        } catch is CancellationError {
            // The view went away. Not an error.
        } catch {
            Log.ui.error("place observation ended: \(error.localizedDescription)")
        }
    }
}

/// Everything shown in a place sheet comes from its current people and their joined places.
struct PlaceSheetContent: Equatable {
    struct Section: Hashable, Identifiable {
        let id: Int64
        let title: String
        let rows: [PersonRow]
    }

    let sections: [Section]

    init(rows: [PersonRow]) {
        sections = Dictionary(grouping: rows, by: { $0.place?.id }).compactMap { id, rows -> Section? in
            guard let id, let place = rows.first?.place else { return nil }
            let here = rows
                .sorted { ($0.meet?.start ?? .distantPast) > ($1.meet?.start ?? .distantPast) }
            return Section(id: id, title: place.name ?? Format.coordinates(place.latitude, place.longitude), rows: here)
        }
        .sorted {
            let first = $0.rows.first?.meet?.start ?? .distantPast
            let second = $1.rows.first?.meet?.start ?? .distantPast
            return first == second ? $0.id < $1.id : first > second
        }
    }

    var title: String {
        if sections.isEmpty {
            return "No meetings here"
        }
        return sections.count == 1 ? sections[0].title : "\(sections.count) places"
    }

    var people: Int {
        sections.reduce(0) { $0 + $1.rows.count }
    }

    var first: Date? {
        sections.flatMap(\.rows).compactMap { $0.meet?.start }.min()
    }

    var last: Date? {
        sections.flatMap(\.rows).compactMap { $0.meet?.start }.max()
    }

    var subtitle: String {
        guard let first, let last else { return Format.peopleCount(people) }
        return "\(Format.peopleCount(people)) · \(Format.yearSpan(first, last))"
    }
}
