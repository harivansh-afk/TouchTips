import MapKit
import SwiftUI
import TouchTipsCore

/// "Elsewhere…": tap the building on the map, or search. Confirms with one glass button at the bottom.
struct PlacePicker: View {
    let origin: CLLocationCoordinate2D?
    let onPick: (PlaceChoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition
    @State private var feature: MapFeature?
    @State private var candidate: PlaceChoice?
    @State private var query = ""
    @State private var results: [PlaceChoice] = []
    @State private var searchTask: Task<Void, Never>?

    init(origin: CLLocationCoordinate2D?, onPick: @escaping (PlaceChoice) -> Void) {
        self.origin = origin
        self.onPick = onPick
        let position: MapCameraPosition = origin.map {
            .region(MKCoordinateRegion(center: $0, latitudinalMeters: 500, longitudinalMeters: 500))
        } ?? .userLocation(fallback: .automatic)
        _camera = State(initialValue: position)
    }

    var body: some View {
        Map(position: $camera, selection: $feature) {
            UserAnnotation()
            if let candidate {
                Marker(candidate.name, coordinate: candidate.coordinate).tint(.white)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .all, showsTraffic: false))
        .mapControls { MapCompass() }
        .grayscale(1)
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .bottom) {
            if let candidate {
                confirmBar(candidate)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.appleMusic, value: candidate)
        .onChange(of: feature) { _, feature in
            guard let feature else { return }
            Task { await resolve(feature) }
        }
        .serifTitle("Elsewhere")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    HapticManager.light()
                    dismiss()
                } label: {
                    Icon("caret-left")
                }
                .accessibilityLabel("Back")
            }
        }
        .searchable(text: $query, prompt: "Search a place")
        .searchSuggestions {
            ForEach(results) { result in
                Button {
                    choose(result)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.name)
                        if let detail = result.detail {
                            Text(detail).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .onChange(of: query) { _, query in
            searchTask?.cancel()
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 2 else { results = []; return }
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                let found = (try? await NearbyPlaces.search(trimmed, near: origin)) ?? []
                guard !Task.isCancelled else { return }
                results = found
            }
        }
    }

    private func confirmBar(_ choice: PlaceChoice) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(choice.name).font(.body.weight(.medium)).lineLimit(1)
                if let detail = choice.detail {
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button {
                HapticManager.medium()
                onPick(choice)
                dismiss()
            } label: {
                Icon("check")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(.white)
            .accessibilityLabel("Use this place")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassEffect(.clear, in: .rect(cornerRadius: 30))
    }

    private func choose(_ choice: PlaceChoice) {
        HapticManager.selection()
        candidate = choice
        query = ""
        results = []
        withAnimation(.appleMusic) {
            camera = .region(MKCoordinateRegion(center: choice.coordinate, latitudinalMeters: 400, longitudinalMeters: 400))
        }
    }

    /// MapFeature is not Sendable, so the map item is fetched here on the main actor.
    private func resolve(_ feature: MapFeature) async {
        guard let item = try? await MKMapItemRequest(feature: feature).mapItem else { return }
        let from = origin.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        guard let choice = PlaceChoice(mapItem: item, from: from) else { return }
        HapticManager.selection()
        candidate = choice
    }
}
