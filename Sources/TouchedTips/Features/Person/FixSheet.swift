import CoreLocation
import SwiftUI
import TouchedTipsCore

/// The user's answer for when and where. One date, then the same Where block the Add sheet draws.
/// Suggestions are your own visits around that day, so the usual fix is one tap.
struct FixSheet: View {
    let row: PersonRow

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var place: PlaceChoice?
    @State private var suggestions: [PlaceChoice] = []
    @State private var problem: String?

    init(row: PersonRow) {
        self.row = row
        _date = State(initialValue: row.meet?.start ?? .now)
        _place = State(initialValue: row.place.map { Self.choice($0) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        label("When")
                        dateRow
                        if let hint = precisionHint {
                            Text(hint)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        label("Where")
                        PlaceChooser(candidates: candidates, selection: $place, origin: origin)
                    }
                    if let problem {
                        Text(problem)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            // Into the keyboard region too, or the translucent keyboard shows a hard edge where the black stops.
            .background { Color.ground.ignoresSafeArea() }
            .serifTitle(row.meet == nil ? "When did you meet?" : "Fix")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        HapticManager.light()
                        dismiss()
                    } label: {
                        Icon(.x)
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        HapticManager.medium()
                        Task { await save() }
                    } label: {
                        Icon(.check)
                    }
                    .accessibilityLabel("Save")
                }
            }
            .task(id: window) { await loadSuggestions() }
        }
        .presentationDetents([.large])
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .kerning(1)
            .foregroundStyle(.secondary)
            .padding(.leading, 6)
    }

    // MARK: - When

    /// The day, as one glass row. The picker is the system's; the row is ours.
    private var dateRow: some View {
        HStack {
            Text(Format.weekday(date))
                .font(.display(22))
            Spacer()
            DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                .labelsHidden()
                .tint(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.clear, in: .rect(cornerRadius: 22))
    }

    /// The row seeds the picker with the first of the month or year when only that much was known.
    private var precisionHint: String? {
        switch row.meet?.precision {
        case .month: "Only the month was known. Pick the day if you remember it."
        case .year: "Only the year was known. Pick the day if you remember it."
        default: nil
        }
    }

    private var window: DateInterval {
        Calendar.current.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 86400)
    }

    // MARK: - Where

    /// The place already on record leads; visits around the day follow.
    private var candidates: [PlaceChoice] {
        var list: [PlaceChoice] = []
        if let existing = row.place {
            list.append(Self.choice(existing))
        }
        for suggestion in suggestions where !list.contains(where: { $0.key == suggestion.key }) {
            list.append(suggestion)
        }
        return list
    }

    private var origin: CLLocationCoordinate2D? {
        (place ?? candidates.first)?.coordinate
    }

    private static func choice(_ place: Place, detail: String = "Current") -> PlaceChoice {
        let name = place.name ?? Format.coordinates(place.latitude, place.longitude)
        return PlaceChoice(place: place, name: name, detail: detail)
    }

    private func loadSuggestions() async {
        let padding = 3 * 3600.0
        let start = window.start.addingTimeInterval(-padding)
        let end = window.end.addingTimeInterval(padding)
        do {
            let visited = try await app.database.reader.read { db in
                try Place.visited(between: start, and: end).limit(8).fetchAll(db)
            }
            suggestions = visited.map { Self.choice($0, detail: "You were here") }
        } catch {
            Log.ui.error("suggestions failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Save

    private func save() async {
        let database = app.database
        do {
            var placeID: Int64?
            if let place {
                placeID = try await database.writer.write { db in
                    try Place.findOrCreate(
                        db, key: place.key, latitude: place.latitude, longitude: place.longitude, name: place.name
                    ).id
                }
            }
            try Ingest.setUserMeet(
                contactID: row.id, start: window.start, end: window.end.addingTimeInterval(-1),
                precision: .day, placeID: placeID, now: .now, to: database
            )
            HapticManager.success()
            dismiss()
        } catch {
            HapticManager.error()
            problem = error.localizedDescription
        }
    }
}
