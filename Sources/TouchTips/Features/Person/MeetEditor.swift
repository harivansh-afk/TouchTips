import CoreLocation
import SwiftUI
import TouchTipsCore

/// When and where, edited on the person screen itself. Every change is saved as the user's answer
/// the moment it is made; there is no button and no sound for it, since the tap that made the
/// change already had one. Suggestions are your own visits around that day.
struct MeetEditor: View {
    let row: PersonRow

    @Environment(AppModel.self) private var app
    @State private var date: Date
    @State private var place: PlaceChoice?
    @State private var suggestions: [PlaceChoice] = []
    @State private var problem: String?

    init(row: PersonRow) {
        self.row = row
        _date = State(initialValue: row.meet?.start ?? .now)
        _place = State(initialValue: row.place.map { PlaceChoice(place: $0, detail: "Current") })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "When").padding(.leading, 6)
                dateRow
                if row.meet == nil {
                    Button("Use today") {
                        date = .now
                        save(dateChanged: true)
                    }
                    .accessibilityIdentifier("meeting.useToday")
                    .padding(.horizontal, 6)
                }
                if let hint = precisionHint {
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Where").padding(.leading, 6)
                PlaceChooser(candidates: candidates, selection: Binding(
                    get: { place },
                    set: {
                        guard $0?.key != place?.key else { return }
                        place = $0
                        save(dateChanged: false)
                    }
                ), origin: origin)
                if row.meet == nil, place != nil {
                    Text("Choose a date to save this place.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }
            }
            if let problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
        }
        .onChange(of: row.meet?.start) { _, start in
            if let start {
                date = start
            }
        }
        .onChange(of: row.place) { _, updated in
            place = updated.map { PlaceChoice(place: $0, detail: "Current") }
        }
        .task(id: window) { await loadSuggestions() }
    }

    // MARK: - When

    /// The day, as one glass row. The picker is the system's; the row is ours. Before any answer
    /// the picker shows today without the row claiming it.
    private var dateRow: some View {
        HStack {
            Text(row.meet == nil ? "Not set" : Format.weekday(date))
                .font(.display(22))
                .foregroundStyle(row.meet == nil ? .secondary : .primary)
            Spacer()
            DatePicker("Date", selection: Binding(
                get: { date },
                set: {
                    date = $0
                    save(dateChanged: true)
                }
            ), in: ...Date.now, displayedComponents: .date)
                .labelsHidden()
                .tint(.white)
                .accessibilityIdentifier("meeting.date")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.clear, in: .rect(cornerRadius: 22))
    }

    /// The picker is seeded with the first of the month or year when only that much was known.
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
            list.append(PlaceChoice(place: existing, detail: "Current"))
        }
        for suggestion in suggestions where !list.contains(where: { $0.key == suggestion.key }) {
            list.append(suggestion)
        }
        return list
    }

    private var origin: CLLocationCoordinate2D? {
        (place ?? candidates.first)?.coordinate
    }

    private func loadSuggestions() async {
        let padding = 3 * 3600.0
        let start = window.start.addingTimeInterval(-padding)
        let end = window.end.addingTimeInterval(padding)
        do {
            let visited = try await app.database.reader.read { db in
                try Place.visited(between: start, and: end).limit(8).fetchAll(db)
            }
            suggestions = visited.map { PlaceChoice(place: $0, detail: "You were here") }
        } catch {
            Log.ui.error("suggestions failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Save

    private func save(dateChanged: Bool) {
        guard dateChanged || row.meet != nil else { return }
        let database = app.database
        do {
            var placeID: Int64?
            if let place {
                placeID = try database.writer.write { db in
                    try Place.findOrCreate(
                        db, key: place.key, latitude: place.latitude, longitude: place.longitude, name: place.name
                    ).id
                }
            }
            if dateChanged {
                try Ingest.setUserMeet(
                    contactID: row.id, start: window.start, end: window.end.addingTimeInterval(-1),
                    precision: .day, placeID: placeID, now: .now, to: database
                )
            } else {
                try Ingest.setUserMeetPlace(contactID: row.id, placeID: placeID, now: .now, to: database)
            }
            problem = nil
        } catch {
            HapticManager.error()
            problem = error.localizedDescription
        }
    }
}
