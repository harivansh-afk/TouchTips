import GRDB
import MapKit
import SwiftUI
import TouchTipsCore

struct MapScreen: View {
    @Environment(AppModel.self) private var app
    @State private var places: [PlaceSummary] = []
    @State private var camera: MapCameraPosition = .automatic
    @State private var selection: Int64?

    /// Muted dark is close to grey; this removes what colour is left. Flip to false if it turns out
    /// SwiftUI's filter does not reach the MapKit layer on device.
    private static let desaturate = true

    var body: some View {
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
            MapUserLocationButton()
            MapCompass()
        }
        .grayscale(Self.desaturate ? 1 : 0)
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
        .sheet(item: selectedPlace) { place in
            PlaceSheet(place: place)
                .presentationDetents([.height(180), .medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .task { await observe() }
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
                places = value
            }
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
