import MapKit
import SwiftUI
import TouchedTipsCore

/// Where. A search field, the map under it, and the places worth one tap as chips beneath.
/// Typing swaps the map for live results; picking one puts it on the map and clears the field.
/// Both sheets that ask for a place draw this, so they answer the same way.
struct PlaceChooser: View {
    /// One-tap places: the visit you are in, businesses nearby, or your visits around the date.
    var candidates: [PlaceChoice]
    @Binding var selection: PlaceChoice?
    /// Where search is biased and where the map looks when nothing is chosen.
    var origin: CLLocationCoordinate2D?
    /// What is going on under the map while there are no candidates yet.
    var note: Note?

    enum Note: Equatable {
        case locating
        case locationOff
    }

    @Environment(\.openURL) private var openURL
    @AppStorage("mapStyle") private var styleChoice = MapStyleChoice.muted
    @State private var query = ""
    @State private var results: [PlaceChoice] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    /// Places picked from search, so they stay on offer after "No place".
    @State private var picked: [PlaceChoice] = []
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    /// Bumped as the camera moves, so the dot is placed again from the map's current frame.
    @State private var cameraTick = 0
    @FocusState private var focused: Bool
    @Namespace private var chips

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSearchField(prompt: "Search a place", text: $query, focused: $focused)
            if trimmedQuery.isEmpty {
                preview
                footer
            } else {
                resultsList
            }
        }
        .animation(.appleMusic, value: trimmedQuery.isEmpty)
        .onChange(of: query) { _, _ in search() }
        .onChange(of: selection, initial: true) { _, chosen in
            if let chosen, !candidates.contains(chosen), !picked.contains(chosen) {
                picked.insert(chosen, at: 0)
            }
            aim(at: chosen?.coordinate ?? origin, animated: true)
        }
        .onChange(of: origin?.latitude, initial: true) { _, _ in
            if selection == nil { aim(at: origin, animated: false) }
        }
    }

    // MARK: - Map

    private var preview: some View {
        mapView
            .frame(height: 210)
            .clipShape(.rect(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22).strokeBorder(Color.hairline)
            }
            .opacity(selection == nil ? 0.6 : 1)
            // Top left, clear of the map's own mark in the bottom corner.
            .overlay(alignment: .topLeading) {
                caption.padding(10)
            }
            .animation(.appleMusic, value: selection == nil)
    }

    /// The dot sits over the map, not in it, so Muted's filter greys the map and not the dot.
    private var mapView: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: MapInteractionModes()) {
                UserAnnotation()
            }
            .mapStyle(styleChoice.style)
            .mapControlVisibility(.hidden)
            .grayscale(styleChoice.grayscale)
            .onMapCameraChange(frequency: .continuous) { _ in cameraTick += 1 }
            .overlay {
                let _ = cameraTick
                if let selection, let point = proxy.convert(selection.coordinate, to: .local) {
                    PinDot(tint: styleChoice.placeTint).position(point)
                }
            }
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(selection?.name ?? "No place")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Text(selection?.detail ?? "Saved with the time only.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.clear, in: .rect(cornerRadius: 16))
    }

    private func aim(at coordinate: CLLocationCoordinate2D?, animated: Bool) {
        let position: MapCameraPosition = coordinate.map {
            .region(MKCoordinateRegion(center: $0, latitudinalMeters: 500, longitudinalMeters: 500))
        } ?? .userLocation(fallback: .automatic)
        if animated {
            withAnimation(.appleMusic) { camera = position }
        } else {
            camera = position
        }
    }

    // MARK: - Chips

    @ViewBuilder
    private var footer: some View {
        switch note {
        case .locating where candidates.isEmpty:
            HStack(spacing: 12) {
                ProgressView()
                Text("Finding where you are").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        case .locationOff where candidates.isEmpty:
            HStack(spacing: 12) {
                Text("Location is off").foregroundStyle(.secondary)
                Spacer()
                Button("Open Settings") {
                    HapticManager.light()
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.glass)
            }
            .padding(.horizontal, 6)
        default:
            GlassEffectContainer(spacing: 8) {
                FlowLayout(spacing: 8) {
                    ForEach(picked + candidates) { choice in
                        chip(choice.name, selected: selection == choice, id: choice.key) {
                            selection = choice
                        }
                    }
                    chip("No place", selected: selection == nil, id: "none", dashed: true) {
                        selection = nil
                    }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, id: String, dashed: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.selection()
            action()
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(selected ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .overlay {
                    if dashed, !selected {
                        Capsule().strokeBorder(Color.dashed, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(.white).interactive() : .clear.interactive(), in: .capsule)
        .glassEffectID(id, in: chips)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Search

    private var resultsList: some View {
        VStack(spacing: 0) {
            if searching, results.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Searching").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            } else if results.isEmpty {
                Text(trimmedQuery.count < 2 ? "Keep typing" : "Nothing found for “\(trimmedQuery)”.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
            } else {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    Button {
                        choose(result)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.name)
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)
                                if let detail = result.detail {
                                    Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 8)
                            Icon(.mapTrifold, size: 16).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.press)
                    if index < results.count - 1 {
                        Rectangle().fill(Color.hairline).frame(height: 1).padding(.leading, 18)
                    }
                }
            }
        }
        .glassEffect(.clear, in: .rect(cornerRadius: 22))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func search() {
        searchTask?.cancel()
        let text = trimmedQuery
        guard text.count >= 2 else {
            results = []
            searching = false
            return
        }
        searching = true
        let near = selection?.coordinate ?? origin
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let found = (try? await NearbyPlaces.search(text, near: near)) ?? []
            guard !Task.isCancelled else { return }
            results = found
            searching = false
        }
    }

    private func choose(_ choice: PlaceChoice) {
        HapticManager.selection()
        selection = choice
        focused = false
        query = ""
        results = []
    }
}

/// The chosen spot: a dot in the map style's tint with a black rim, so it reads on any map.
private struct PinDot: View {
    let tint: Color

    var body: some View {
        Circle()
            .fill(tint)
            .overlay { Circle().strokeBorder(Color.ground, lineWidth: 3) }
            .frame(width: 18, height: 18)
            .shadow(color: .black.opacity(0.5), radius: 5, y: 2)
    }
}
