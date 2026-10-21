import MapKit
import TouchTipsCore

/// MapKit place search for the place chooser. Main actor: MapKit asserts when a search starts off the
/// main thread, and every caller is there anyway.
@MainActor
enum PlaceSearch {
    /// Free-text search, biased to a few kilometres around `coordinate` when there is one.
    static func search(_ query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [PlaceChoice] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        if let coordinate {
            request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 5000, longitudinalMeters: 5000)
        }
        let response = try await MKLocalSearch(request: request).start()
        return Array(response.mapItems.compactMap(PlaceChoice.init(mapItem:)).prefix(8))
    }
}
