import SwiftUI
import TouchedTipsCore

/// Everyone met at one place, newest first.
struct PlaceSheet: View {
    let place: PlaceSummary
    /// Called with a contact ID when a row is tapped. The map closes the sheet, then pushes.
    let onOpen: (String) -> Void

    @Environment(AppModel.self) private var app
    @State private var rows: [PersonRow] = []

    var body: some View {
        List {
            // The heading is a row on the left, under the grabber. No bar, nothing centred.
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name ?? Format.coordinates(place.latitude, place.longitude))
                        .font(.display(26))
                        .lineLimit(2)
                    Text("\(place.people) people · \(Format.yearSpan(place.first, place.last))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .listRowInsets(EdgeInsets(top: 18, leading: 20, bottom: 10, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            let indexed = rows.indexedRows()
            ForEach(indexed) { entry in
                let row = entry.item
                Button {
                    HapticManager.selection()
                    onOpen(row.id)
                } label: {
                    PersonRowView(row: row)
                }
                .buttonStyle(.press)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparatorTint(.hairline)
                .listRowSeparator(entry.index == 0 ? .hidden : .visible, edges: .top)
                .listRowSeparator(entry.index == indexed.count - 1 ? .hidden : .visible, edges: .bottom)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .task { await observe() }
    }

    private func observe() async {
        let placeID = place.id
        let observation = ValueObservation.tracking { db in
            try Person.rows(atPlace: placeID).fetchAll(db)
        }
        do {
            for try await value in observation.values(in: app.database.reader) {
                let sorted = value.sorted { ($0.meet?.start ?? .distantPast) > ($1.meet?.start ?? .distantPast) }
                if rows != sorted { rows = sorted }
            }
        } catch is CancellationError {
            // The view went away. Not an error.
        } catch {
            Log.ui.error("place observation ended: \(error.localizedDescription)")
        }
    }
}
