import MapKit
import SwiftUI
import TouchTipsCore

/// MapKit lookups for the Add sheet and the notification. Main actor: MapKit asserts when a search starts off
/// the main thread, and every caller is there anyway.
@MainActor
enum NearbyPlaces {
    /// Businesses within `radius` metres of a point, nearest first.
    static func around(
        _ coordinate: CLLocationCoordinate2D, radius: CLLocationDistance = 150, limit: Int = 4
    ) async throws -> [PlaceChoice] {
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: radius)
        let response = try await MKLocalSearch(request: request).start()
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return Array(
            response.mapItems
                .compactMap { PlaceChoice(mapItem: $0, from: origin) }
                .sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
                .prefix(limit)
        )
    }

    /// Free-text search, biased to a few kilometres around `coordinate` when there is one.
    static func search(_ query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [PlaceChoice] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        if let coordinate {
            request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 5000, longitudinalMeters: 5000)
        }
        let response = try await MKLocalSearch(request: request).start()
        let origin = coordinate.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        return Array(response.mapItems.compactMap { PlaceChoice(mapItem: $0, from: origin) }.prefix(8))
    }
}
