import MapKit
import Observation
import UIKit

/// One snapshot per style of roughly where the map is, rendered once and kept for the session.
/// The snapshotter downloads Apple's tiles for each style, satellite and hybrid being the heavy
/// ones, so the cache is coarse and the four are fetched as soon as the camera settles, well before
/// the sheet is opened.
@MainActor
@Observable
final class MapSnapshots {
    private var images: [String: UIImage] = [:]
    private var inFlight: Set<String> = []

    static let tileSize = CGSize(width: 160, height: 108)

    func image(for choice: MapStyleChoice, region: MKCoordinateRegion) -> UIImage? {
        images[Self.key(choice, region)]
    }

    /// Start all four for this region if they are not already cached or in flight.
    func prefetch(region: MKCoordinateRegion) {
        for choice in MapStyleChoice.allCases {
            load(choice, region: region, size: Self.tileSize)
        }
    }

    func load(_ choice: MapStyleChoice, region: MKCoordinateRegion, size: CGSize) {
        let key = Self.key(choice, region)
        guard images[key] == nil, !inFlight.contains(key) else { return }
        inFlight.insert(key)
        let rounded = Self.rounded(region)
        Task.detached(priority: .userInitiated) {
            let image = try? await Self.render(choice, region: rounded, size: size)
            await MainActor.run {
                self.inFlight.remove(key)
                if let image { self.images[key] = image }
            }
        }
    }

    nonisolated private static func render(
        _ choice: MapStyleChoice, region: MKCoordinateRegion, size: CGSize
    ) async throws -> UIImage {
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.preferredConfiguration = choice.configuration
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        let snapshot = try await MKMapSnapshotter(options: options).start()
        return snapshot.image
    }

    /// Two decimals of centre (about a kilometre) and one of span: a pan across the block does not
    /// throw the pictures away.
    nonisolated private static func rounded(_ region: MKCoordinateRegion) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (region.center.latitude * 100).rounded() / 100,
                longitude: (region.center.longitude * 100).rounded() / 100
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((region.span.latitudeDelta * 10).rounded() / 10, 0.01),
                longitudeDelta: max((region.span.longitudeDelta * 10).rounded() / 10, 0.01)
            )
        )
    }

    nonisolated private static func key(_ choice: MapStyleChoice, _ region: MKCoordinateRegion) -> String {
        let r = rounded(region)
        return String(
            format: "%@|%.2f,%.2f|%.1f,%.1f",
            choice.rawValue, r.center.latitude, r.center.longitude, r.span.latitudeDelta, r.span.longitudeDelta
        )
    }
}
