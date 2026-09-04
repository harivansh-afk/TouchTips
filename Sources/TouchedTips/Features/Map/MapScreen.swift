import MapKit
import SwiftUI
import TouchedTipsCore

struct MapScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @State private var places: [PlaceSummary] = []
    @State private var camera: MapCameraPosition = .automatic
    /// The place whose sheet is open, or whose pin is held while it opens.
    @State private var selection: Int64?
    /// Bumped as the camera moves, so the pins are placed again from the map's current frame.
    @State private var cameraTick = 0
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
        MapReader { proxy in
            Map(position: $camera) {
                UserAnnotation()
            }
            .mapStyle(styleChoice.style)
            .mapControls {
                MapCompass()
            }
            .grayscale(styleChoice.grayscale)
            .onMapCameraChange(frequency: .continuous) { _ in cameraTick += 1 }
            .overlay { pins(in: proxy) }
        }
        .aboveTabBar()
        .overlay(alignment: .topLeading) {
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

    /// The pins sit over the map, not in it, so Muted's filter greys the map and not the pins.
    /// Reading the tick makes this body run again on every camera move. Points are taken in
    /// global space and moved into the layer's own, so no safe area can put a pin off its target.
    private func pins(in proxy: MapProxy) -> some View {
        let _ = cameraTick
        return GeometryReader { layer in
            let origin = layer.frame(in: .global).origin
            ForEach(places) { place in
                if let point = proxy.convert(place.coordinate, to: .global) {
                    Button {
                        open(place)
                    } label: {
                        PlacePin(
                            place: place,
                            image: place.soleContactID.flatMap(app.photos.image(for:)),
                            tint: styleChoice.placeTint,
                            selected: selection == place.id
                        )
                    }
                    .buttonStyle(.plain)
                    .position(x: point.x - origin.x, y: point.y - origin.y)
                }
            }
        }
        .ignoresSafeArea()
    }

    /// One person is the pin, so the tap goes straight to them; more open the sheet.
    private func open(_ place: PlaceSummary) {
        HapticManager.selection()
        if let contactID = place.soleContactID {
            router.open(person: contactID)
        } else {
            selection = place.id
        }
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
