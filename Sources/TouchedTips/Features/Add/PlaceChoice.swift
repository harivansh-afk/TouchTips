import CoreLocation
import MapKit
import TouchedTipsCore

/// A place the Add sheet can attach: the visit you are in, a business nearby, or one picked on the map.
struct PlaceChoice: Identifiable, Hashable, Sendable {
    var key: String
    var name: String
    var latitude: Double
    var longitude: Double
    /// One line under the chip row: "You are here · since 09:02", "40 m".
    var detail: String?
    var distance: Double?

    var id: String { key }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(key: String, name: String, latitude: Double, longitude: Double, detail: String? = nil, distance: Double? = nil) {
        self.key = key
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.detail = detail
        self.distance = distance
    }

    /// The place behind the visit you are in.
    init(place: Place, name: String, detail: String?) {
        self.init(key: place.key, name: name, latitude: place.latitude, longitude: place.longitude, detail: detail)
    }

    /// A map item from a nearby search, a text search, or a tap on the map.
    nonisolated init?(mapItem item: MKMapItem, from origin: CLLocation?) {
        guard let name = item.name ?? item.address?.shortAddress else { return nil }
        let location = item.location
        let distance = origin?.distance(from: location)
        self.init(
            key: item.identifier.map { PlaceKey.apple($0.rawValue) }
                ?? PlaceKey.cell(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            name: name,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            detail: distance.map(Format.distance),
            distance: distance
        )
    }
}
