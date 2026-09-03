import GRDB
import MapKit
import SwiftUI
import TouchTipsCore

/// The user's answer for when and where. Precision first, because "sometime in 2023" is a real answer.
struct FixSheet: View {
    let row: PersonRow

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var precision: Choice
    @State private var date: Date
    @State private var place: PlacePick
    @State private var suggestions: [Place] = []
    @State private var query = ""
    @State private var found: [FoundPlace] = []
    @State private var problem: String?

    init(row: PersonRow) {
        self.row = row
        _precision = State(initialValue: Choice(row.meet?.precision))
        _date = State(initialValue: row.meet?.start ?? .now)
        _place = State(initialValue: row.place.map(PlacePick.existing) ?? .none)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("When") {
                    Picker("Precision", selection: $precision) {
                        ForEach(Choice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                    if precision != .unknown {
                        DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                    }
                }

                if precision != .unknown {
                    Section("Where") {
                        Picker("Where", selection: $place) {
                            ForEach(suggestions) { suggestion in
                                option(suggestion.name ?? Format.coordinates(suggestion.latitude, suggestion.longitude), detail: "You were here")
                                    .tag(PlacePick.existing(suggestion))
                            }
                            ForEach(found) { result in
                                option(result.name, detail: result.detail ?? "Search result")
                                    .tag(PlacePick.found(result))
                            }
                            Text("No place").tag(PlacePick.none)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()

                        TextField("Search a place", text: $query)
                            .submitLabel(.search)
                            .onSubmit { Task { await search() } }
                    }
                }

                if let problem {
                    Section { Text(problem).foregroundStyle(.secondary) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle(row.meet == nil ? "When did you meet?" : "Fix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                }
            }
            .task(id: window) { await loadSuggestions() }
        }
        .presentationDetents([.large])
    }

    private func option(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: - Time

    private var window: DateInterval? {
        let calendar = Calendar.current
        switch precision {
        case .day: return calendar.dateInterval(of: .day, for: date)
        case .month: return calendar.dateInterval(of: .month, for: date)
        case .year: return calendar.dateInterval(of: .year, for: date)
        case .unknown: return nil
        }
    }

    // MARK: - Places

    private func loadSuggestions() async {
        guard let window else {
            suggestions = []
            return
        }
        let padding = 3 * 3600.0
        let start = window.start.addingTimeInterval(-padding)
        let end = window.end.addingTimeInterval(padding)
        do {
            suggestions = try await app.database.reader.read { db in
                try Place.visited(between: start, and: end).limit(8).fetchAll(db)
            }
        } catch {
            Log.ui.error("suggestions failed: \(error.localizedDescription)")
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.pointOfInterest, .address]
        if let near = suggestions.first {
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: near.latitude, longitude: near.longitude),
                latitudinalMeters: 20_000, longitudinalMeters: 20_000
            )
        }
        do {
            let response = try await MKLocalSearch(request: request).start()
            found = response.mapItems.prefix(6).map { item in
                FoundPlace(
                    name: item.name ?? text,
                    detail: item.addressRepresentations?.cityWithContext,
                    latitude: item.location.coordinate.latitude,
                    longitude: item.location.coordinate.longitude
                )
            }
            problem = found.isEmpty ? "Nothing found for “\(text)”." : nil
        } catch {
            problem = error.localizedDescription
        }
    }

    // MARK: - Save

    private func save() async {
        let database = app.database
        do {
            guard let window else {
                try Ingest.clearMeet(contactID: row.id, to: database)
                dismiss()
                return
            }
            let placeID: Int64? = switch place {
            case .none:
                nil
            case .existing(let existing):
                existing.id
            case .found(let result):
                try await database.writer.write { db in
                    try Place.findOrCreate(
                        db, key: PlaceKey.cell(latitude: result.latitude, longitude: result.longitude),
                        latitude: result.latitude, longitude: result.longitude, name: result.name
                    ).id
                }
            }
            try Ingest.setUserMeet(
                contactID: row.id, start: window.start, end: window.end.addingTimeInterval(-1),
                precision: precision.precision, placeID: placeID, now: .now, to: database
            )
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }
}

private enum Choice: Hashable, CaseIterable, Identifiable {
    case day, month, year, unknown

    var id: Self { self }

    init(_ precision: Precision?) {
        switch precision {
        case .exact, .day, nil: self = .day
        case .month: self = .month
        case .year: self = .year
        }
    }

    var title: String {
        switch self {
        case .day: "Day"
        case .month: "Month"
        case .year: "Year"
        case .unknown: "Unknown"
        }
    }

    /// Only valid when not `.unknown`.
    var precision: Precision {
        switch self {
        case .day, .unknown: .day
        case .month: .month
        case .year: .year
        }
    }
}

private struct FoundPlace: Hashable, Identifiable {
    let name: String
    let detail: String?
    let latitude: Double
    let longitude: Double

    var id: String { "\(latitude),\(longitude)" }
}

private enum PlacePick: Hashable {
    case none
    case existing(Place)
    case found(FoundPlace)
}
