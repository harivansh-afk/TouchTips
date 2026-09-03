import MapKit
import SwiftUI
import TouchTipsCore

struct MapScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @State private var places: [PlaceSummary] = []
    @State private var camera: MapCameraPosition = .automatic
    @State private var selection: Int64?
    /// A person tapped in the place sheet. Pushed once the sheet has finished closing.
    @State private var pendingPerson: String?
    /// The place whose sheet was open when a person was tapped, so back can reopen it.
    @State private var lastPlace: Int64?

    var body: some View {
        map
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
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls {
            MapCompass()
        }
        // No grayscale filter: it re-rendered the whole MapKit layer every frame and made pins feel slow.
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
            .padding(16)
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
                .presentationDragIndicator(.hidden)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .task { await observe() }
    }

    private func pushPendingPerson() {
        guard let contactID = pendingPerson else { return }
        pendingPerson = nil
        router.open(person: contactID, fromPlace: lastPlace)
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
