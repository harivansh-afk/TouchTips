import SwiftUI
import TouchTipsCore

/// Everyone met at one pin. One place is a list, newest first; several places, merged at this
/// zoom, are the same list under a heading per place, the place with the newest meeting first.
struct PlaceSheet: View {
    let group: PlaceGroup
    /// Called with a contact ID when a row is tapped. The map closes the sheet, then pushes.
    let onOpen: (String) -> Void

    @Environment(AppModel.self) private var app
    @State private var sections: [Section] = []

    private struct Section: Hashable, Identifiable {
        let id: Int64
        let title: String
        let rows: [PersonRow]
    }

    var body: some View {
        List {
            // The heading is a row on the left, under the grabber. No bar, nothing centred.
            SwiftUI.Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                        .font(.display(26))
                        .lineLimit(2)
                    Text("\(Format.peopleCount(group.people)) · \(Format.yearSpan(group.first, group.last))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .listRowInsets(EdgeInsets(top: 18, leading: 20, bottom: 10, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            ForEach(sections) { section in
                if sections.count > 1 {
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
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowSeparatorTint(.hairline)
            .listRowSeparator(entry.index == 0 ? .hidden : .visible, edges: .top)
            .listRowSeparator(entry.index == indexed.count - 1 ? .hidden : .visible, edges: .bottom)
        }
    }

    private func observe() async {
        let places = group.places
        let observation = ValueObservation.tracking { db in
            try Person.rows(atPlaces: places.map(\.id)).fetchAll(db)
        }
        do {
            for try await value in observation.values(in: app.database.reader) {
                let next = Self.sections(of: value, at: places)
                if sections != next { sections = next }
            }
        } catch is CancellationError {
            // The view went away. Not an error.
        } catch {
            Log.ui.error("place observation ended: \(error.localizedDescription)")
        }
    }

    /// Newest first within a place; places by their newest. A place nobody is at any more is left out.
    private static func sections(of rows: [PersonRow], at places: [PlaceSummary]) -> [Section] {
        places.compactMap { place in
            let here = rows
                .filter { $0.place?.id == place.id }
                .sorted { ($0.meet?.start ?? .distantPast) > ($1.meet?.start ?? .distantPast) }
            guard !here.isEmpty else { return nil }
            return Section(id: place.id, title: place.name ?? Format.coordinates(place.latitude, place.longitude), rows: here)
        }
        .sorted { ($0.rows.first?.meet?.start ?? .distantPast) > ($1.rows.first?.meet?.start ?? .distantPast) }
    }
}
