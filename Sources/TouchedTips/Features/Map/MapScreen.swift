import MapKit
import SwiftUI
import TouchedTipsCore

struct MapScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @State private var places: [PlaceSummary] = []
    @State private var camera: MapCameraPosition = .automatic
    @State private var selection: Int64?
    @AppStorage("mapStyle") private var styleChoice = MapStyleChoice.muted
    /// A person tapped in the place sheet. Pushed once the sheet has finished closing.
    @State private var pendingPerson: String?
    /// The place whose sheet was open when a person was tapped, so back can reopen it.
    @State private var lastPlace: Int64?

    var body: some View {
        NavigationStack(path: router.path(for: .map)) {
            map
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Destination.self) { destination in
                    DestinationView(destination: destination)
                }
        }
        // Back from a person lands here with the same place sheet open again.
        .onChange(of: router.paths[.map]?.count ?? 0) { _, count in
            guard count == 0, let place = lastPlace else { return }
            lastPlace = nil
            selection = place
        }
    }

    private var map: some View {
        Map(position: $camera, selection: $selection) {
            ForEach(places) { place in
                Marker(place.name ?? "", monogram: Text(place.people, format: .number), coordinate: place.coordinate)
                    .tint(place.witnessed ? .white : .gray)
                    .tag(place.id)
            }
            UserAnnotation()
        }
        .mapStyle(styleChoice.style)
        .mapControls {
            MapCompass()
        }
        // Muted is monotone by decision. The filter costs a re-render of the map layer per frame, so
        // it applies to that one style only; the other three are MapKit's own colour.
        .grayscale(styleChoice == .muted ? 1 : 0)
        .overlay(alignment: .topTrailing) {
            Button {
                HapticManager.light()
                withAnimation(.appleMusic) {
                    camera = .userLocation(fallback: .automatic)
                }
            } label: {
                Icon(.navigationArrow)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.clear.interactive(), in: .circle)
            .accessibilityLabel("Recentre on me")
            .padding(.horizontal, 16)
            .padding(.top, 2)
        }
        .onChange(of: selection) { _, current in
            if current != nil { HapticManager.selection() }
        }
        .onChange(of: router.pendingPlace, initial: true) { _, _ in showPendingPlace() }
        .onChange(of: places) { _, _ in showPendingPlace() }
        .overlay {
            if places.isEmpty {
                ContentUnavailableView(
                    "Nothing placed yet",
                    systemImage: "mappin.slash",
                    description: Text("A place appears here once someone was met there.")
                )
                .allowsHitTesting(false)
            }
        }
        .sheet(item: selectedPlace, onDismiss: pushPendingPerson) { place in
            PlaceSheet(place: place) { contactID in
                pendingPerson = contactID
                lastPlace = place.id
                selection = nil
            }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .task { await observe() }
    }


    private func pushPendingPerson() {
        guard let contactID = pendingPerson else { return }
        pendingPerson = nil
        router.open(person: contactID)
    }

    /// Selects the place another screen asked for, once it is in the list.
    private func showPendingPlace() {
        guard let id = router.pendingPlace, let place = places.first(where: { $0.id == id }) else { return }
        router.pendingPlace = nil
        withAnimation(.appleMusic) {
            camera = .region(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 600, longitudinalMeters: 600))
        }
        selection = id
    }

    private var selectedPlace: Binding<PlaceSummary?> {
        Binding(
            get: { places.first { $0.id == selection } },
            set: { selection = $0?.id }
        )
    }

    private func observe() async {
        let observation = ValueObservation.tracking { db in try PlaceSummary.all().fetchAll(db) }
        do {
            for try await value in observation.values(in: app.database.reader) {
                if places != value { places = value }
            }
        } catch is CancellationError {
            // The view went away. Not an error.
        } catch {
            Log.ui.error("map observation ended: \(error.localizedDescription)")
        }
    }
}

extension PlaceSummary {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
