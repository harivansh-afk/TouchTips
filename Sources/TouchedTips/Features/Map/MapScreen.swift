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
                Annotation(place.name ?? "", coordinate: place.coordinate, anchor: .center) {
                    PlacePin(
                        place: place,
                        image: place.soleContactID.flatMap(app.photos.image(for:)),
                        selected: selection == place.id
                    )
                }
                .tag(place.id)
                .annotationTitles(.hidden)
            }
            UserAnnotation()
        }
        .mapStyle(styleChoice.style)
        .mapControls {
            MapCompass()
        }
        // The map draws its own bottom-left mark against its safe area, and the bar's inset on the
        // tab view does not reach it. Told here, it keeps the mark and the sheets above the bar.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: TabBar.contentInset)
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
        .overlay {
            if places.isEmpty {
                emptyState
                    .transition(.blurReplace)
            }
        }
        .animation(.appleMusic, value: places.isEmpty)
        .onChange(of: selection) { _, current in
            guard let current, let place = places.first(where: { $0.id == current }) else { return }
            HapticManager.selection()
            // One person: they are the pin, so the tap goes straight to them.
            if let contactID = place.soleContactID {
                selection = nil
                router.open(person: contactID)
            }
        }
        .onChange(of: router.pendingPlace, initial: true) { _, _ in showPendingPlace() }
        .onChange(of: places, initial: true) { _, places in
            for id in places.compactMap(\.soleContactID) { app.photos.load(id) }
            showPendingPlace()
        }
        .sheet(item: sheetPlace, onDismiss: pushPendingPerson) { place in
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

    /// One line in the app's voice, centred on the map, in place of a system placeholder.
    private var emptyState: some View {
        VStack(spacing: 2) {
            Text("Nowhere yet")
                .font(.display(24))
            Text("The map fills in as you meet people.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .glassEffect(.clear, in: .rect(cornerRadius: 24))
        .allowsHitTesting(false)
    }

    private func pushPendingPerson() {
        guard let contactID = pendingPerson else { return }
        pendingPerson = nil
        router.open(person: contactID)
    }

    /// Centres on the place another screen asked for, once it is in the list. A place with one
    /// person is only centred, or the pin would push the screen that just sent us here.
    private func showPendingPlace() {
        guard let id = router.pendingPlace, let place = places.first(where: { $0.id == id }) else { return }
        router.pendingPlace = nil
        withAnimation(.appleMusic) {
            camera = .region(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 600, longitudinalMeters: 600))
        }
        if place.soleContactID == nil { selection = id }
    }

    /// The sheet is for places with more than one person; a single person is pushed instead.
    private var sheetPlace: Binding<PlaceSummary?> {
        Binding(
            get: { places.first { $0.id == selection && $0.soleContactID == nil } },
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
