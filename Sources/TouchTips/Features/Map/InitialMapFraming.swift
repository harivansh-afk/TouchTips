import MapKit

/// Saved pins are overlays, so MapKit's automatic camera cannot frame them itself.
struct InitialMapFraming {
    private var available = true

    mutating func cancel() {
        available = false
    }

    /// Only the first database snapshot may choose a camera, unless the user already chose one.
    mutating func region(
        afterLoading coordinates: [CLLocationCoordinate2D],
        hasPendingPlace: Bool,
        positionedByUser: Bool
    ) -> MKCoordinateRegion? {
        guard available else { return nil }
        available = false
        guard !hasPendingPlace, !positionedByUser else { return nil }
        return Self.region(containing: coordinates)
    }

    static func region(containing coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        let valid = coordinates.filter {
            $0.latitude.isFinite && $0.longitude.isFinite && CLLocationCoordinate2DIsValid($0)
        }
        guard let minimumLatitude = valid.map(\.latitude).min(),
              let maximumLatitude = valid.map(\.latitude).max() else { return nil }

        // Remove the largest empty longitude gap, including the gap across the dateline.
        // This keeps places at 179 and -179 degrees together instead of showing most of Earth.
        let longitudes = valid.map { $0.longitude < 0 ? $0.longitude + 360 : $0.longitude }.sorted()
        var largestGap = -Double.infinity
        var start = longitudes[0]
        for index in longitudes.indices {
            let next = index + 1 < longitudes.count ? longitudes[index + 1] : longitudes[0] + 360
            let gap = next - longitudes[index]
            if gap > largestGap {
                largestGap = gap
                start = next.truncatingRemainder(dividingBy: 360)
            }
        }
        let longitudeSpan = 360 - largestGap
        var longitude = (start + longitudeSpan / 2).truncatingRemainder(dividingBy: 360)
        if longitude > 180 {
            longitude -= 360
        }
        let center = CLLocationCoordinate2D(
            latitude: (minimumLatitude + maximumLatitude) / 2,
            longitude: longitude
        )
        // A single place still needs street context, and the padding leaves room for the pins.
        let minimum = MKCoordinateRegion(center: center, latitudinalMeters: 600, longitudinalMeters: 600)
        let latitudeDelta = min(180, max(minimum.span.latitudeDelta, (maximumLatitude - minimumLatitude) * 1.35))
        let longitudeDelta = min(360, max(minimum.span.longitudeDelta, longitudeSpan * 1.35))
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: max(-90 + latitudeDelta / 2, min(90 - latitudeDelta / 2, center.latitude)),
                longitude: center.longitude
            ),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }
}
