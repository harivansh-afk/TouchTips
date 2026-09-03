import SwiftUI
import TouchTipsCore

/// Everyone met at one place, newest first.
struct PlaceSheet: View {
    let place: PlaceSummary

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [PersonRow] = []

    var body: some View {
        NavigationStack {
            List(rows) { row in
                NavigationLink(value: row.id) {
                    PersonRowView(row: row)
                }
                .listRowSeparatorTint(.white.opacity(0.12))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle(place.name ?? Format.coordinates(place.latitude, place.longitude))
            .navigationSubtitle("\(place.people) people · \(Format.yearSpan(place.first, place.last))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        HapticManager.light()
                        dismiss()
                    } label: {
                        Icon("x")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .navigationDestination(for: String.self) { contactID in
                PersonView(contactID: contactID)
            }
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
