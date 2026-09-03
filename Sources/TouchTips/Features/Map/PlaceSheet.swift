import SwiftUI
import TouchTipsCore

/// Everyone met at one place, newest first.
struct PlaceSheet: View {
    let place: PlaceSummary
    /// Called with a contact ID when a row is tapped. The map closes the sheet, then pushes.
    let onOpen: (String) -> Void

    @Environment(AppModel.self) private var app
    @State private var rows: [PersonRow] = []

    var body: some View {
        NavigationStack {
            List(rows) { row in
                Button {
                    HapticManager.selection()
                    onOpen(row.id)
                } label: {
                    PersonRowView(row: row)
                }
                .buttonStyle(.press)
                .listRowSeparatorTint(.hairline)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .serifTitle(
                place.name ?? Format.coordinates(place.latitude, place.longitude),
                subtitle: "\(place.people) people · \(Format.yearSpan(place.first, place.last))"
            )
            .task { await observe() }
        }
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
