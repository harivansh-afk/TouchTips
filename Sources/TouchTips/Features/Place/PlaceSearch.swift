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

    /// Places of interest around a fix, nearest first. The radius grows with the fix's uncertainty,
    /// so a vague fix still reaches the place the phone is really in.
    static func nearby(_ location: CLLocation, limit: Int = 4) async -> [PlaceChoice] {
        let radius = min(max(location.horizontalAccuracy, 40), LocationAccess.maxUncertainty)
        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: radius)
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return Array(
            response.mapItems
                .sorted { location.distance(from: $0.location) < location.distance(from: $1.location) }
                .compactMap(PlaceChoice.init(mapItem:))
                .prefix(limit)
        )
    }

    /// The one place to name a fix by: the nearest place of interest, else the street address.
    static func here(_ location: CLLocation) async -> PlaceChoice? {
        if let nearest = await nearby(location, limit: 1).first {
            return nearest
        }
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first
        else { return nil }
        return PlaceChoice(mapItem: item)
    }
}
