import CoreLocation
import MapKit
import TouchTipsCore

/// A place a meeting can be attached to: one on record, or one found by search.
struct PlaceChoice: Identifiable, Hashable, Sendable {
    var key: String
    var name: String
    var latitude: Double
    var longitude: Double
    /// One line under the name: the address for a searched place.
    var detail: String?

    var id: String {
        key
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(
        key: String,
        name: String,
        latitude: Double,
        longitude: Double,
        detail: String? = nil
    ) {
        self.key = key
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.detail = detail
    }

    /// A place on record, under the name it has; a friendly label when it has none.
    init(place: Place, detail: String?) {
        self.init(
            key: place.key,
            name: Format.placeLabel(place.name, latitude: place.latitude, longitude: place.longitude),
            latitude: place.latitude,
            longitude: place.longitude,
            detail: detail
        )
    }

    /// One suggestion per visible place name, with the selected record taking priority.
    /// Older records and map searches can give the same location different storage keys.
    static func suggestions(picked: [Self], candidates: [Self], selection: Self? = nil) -> [Self] {
        var seenKeys: Set<String> = []
        var seenNames: Set<String> = []
        return ([selection].compactMap { $0 } + picked + candidates).compactMap { choice in
            let label = Format.placeLabel(choice.name, latitude: choice.latitude, longitude: choice.longitude)
            guard label != "Meeting location" else { return nil }
            let normalizedName = label.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard !seenKeys.contains(choice.key), !seenNames.contains(normalizedName) else { return nil }
            seenKeys.insert(choice.key)
            seenNames.insert(normalizedName)
            var suggestion = choice
            suggestion.name = label
            return suggestion
        }
    }

    /// A map item from a text search.
    nonisolated init?(mapItem item: MKMapItem) {
        guard let name = item.name ?? item.address?.shortAddress else { return nil }
        let location = item.location
        // The whole address, on one line, so two branches of one chain can be told apart.
        var address = item.address?.fullAddress.replacingOccurrences(of: "\n", with: ", ")
        if address == nil || address == name {
            address = item.addressRepresentations?.cityWithContext
        }
        self.init(
            key: item.identifier.map { PlaceKey.apple($0.rawValue) }
                ?? PlaceKey.cell(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            name: name,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            detail: address
        )
    }
}
