import MapKit
import SwiftUI
import TouchTipsCore

struct MapScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @State private var places: [PlaceSummary] = []
    @State private var camera: MapCameraPosition = .automatic
    /// The pin whose sheet is open, or which is held while it opens.
    @State private var selection: PlaceGroup?
    /// Bumped as the camera moves, so the pins are placed again from the map's current frame.
    @State private var cameraTick = 0
    @AppStorage("mapStyle") private var styleChoice = MapStyleChoice.muted
    /// A person tapped in the place sheet. Pushed once the sheet has finished closing.
    @State private var pendingPerson: String?
    /// The pin whose sheet was open when a person was tapped, so back can reopen it.
    @State private var lastGroup: PlaceGroup?

    /// Two pins closer than this, centre to centre, become one. A pin is 44 points across.
    private static let mergeDistance: CGFloat = 52

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
            guard count == 0, let group = lastGroup else { return }
            lastGroup = nil
            selection = group
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
            Icon(.navigationArrow)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .glassEffect(.clear.interactive(), in: .circle)
                .contentShape(.circle)
                .tapOverMap {
                    HapticManager.light()
                    withAnimation(.appleMusic) {
                        camera = .userLocation(fallback: .automatic)
                    }
                }
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
        .sheet(item: $selection, onDismiss: pushPendingPerson) { group in
            PlaceSheet(group: group) { contactID in
                pendingPerson = contactID
                lastGroup = group
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
    /// Places whose pins would overlap are drawn as one; the split and merge cross-fade.
    private func pins(in proxy: MapProxy) -> some View {
        let _ = cameraTick
        return GeometryReader { layer in
            let origin = layer.frame(in: .global).origin
            let pins = clustered(in: proxy)
            ZStack {
                ForEach(pins, id: \.group.id) { pin in
                    PlacePin(
                        group: pin.group,
                        image: pin.group.soleContactID.flatMap(app.photos.image(for:)),
                        tint: styleChoice.placeTint,
                        selected: selection?.id == pin.group.id
                    )
                    .contentShape(.circle)
                    .tapOverMap { open(pin.group) }
                    .position(x: pin.point.x - origin.x, y: pin.point.y - origin.y)
                    .transition(.blurReplace)
                }
            }
            .animation(.appleMusic, value: pins.map(\.group.id))
        }
        .ignoresSafeArea()
    }

    private struct Pin {
        let group: PlaceGroup
        let point: CGPoint
    }

    /// Greedy, in screen space: each place joins the first group whose centre is within reach,
    /// or starts its own. Places go in id order, so the same zoom always makes the same groups.
    private func clustered(in proxy: MapProxy) -> [Pin] {
        var groups: [(places: [PlaceSummary], sum: CGPoint)] = []
        for place in places.sorted(by: { $0.id < $1.id }) {
            guard let point = proxy.convert(place.coordinate, to: .global) else { continue }
            let near = groups.firstIndex { group in
                let count = CGFloat(group.places.count)
                return hypot(group.sum.x / count - point.x, group.sum.y / count - point.y) < Self.mergeDistance
            }
            if let near {
                groups[near].places.append(place)
                groups[near].sum.x += point.x
                groups[near].sum.y += point.y
            } else {
                groups.append((places: [place], sum: point))
            }
        }
        return groups.map { group in
            let count = CGFloat(group.places.count)
            return Pin(group: PlaceGroup(places: group.places), point: CGPoint(x: group.sum.x / count, y: group.sum.y / count))
        }
    }

    /// One person is the pin, so the tap goes straight to them; more open the sheet.
    private func open(_ group: PlaceGroup) {
        HapticManager.selection()
        if let contactID = group.soleContactID {
            router.open(person: contactID)
        } else {
            selection = group
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
        if place.soleContactID == nil { selection = PlaceGroup(places: [place]) }
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

private extension View {
    /// A tap on something drawn over the map. On iOS 26 a Button or onTapGesture over a Map never
    /// fires: the map's own recognisers take the touch first (FB19394663, in the iOS 26 release
    /// notes). A gesture declared simultaneous is the documented way through.
    func tapOverMap(_ action: @escaping () -> Void) -> some View {
        simultaneousGesture(TapGesture().onEnded(action))
            .accessibilityAddTraits(.isButton)
    }
}

extension PlaceSummary {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
