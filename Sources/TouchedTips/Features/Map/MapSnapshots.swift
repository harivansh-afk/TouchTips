import MapKit
import Observation
import UIKit

/// One snapshot per style of the region the map is showing, rendered once and kept for the session.
/// Four live maps in the sheet would run four renderers at once; a snapshot is a picture.
@MainActor
@Observable
final class MapSnapshots {
    private var images: [String: UIImage] = [:]
    private var inFlight: Set<String> = []

    func image(for choice: MapStyleChoice, region: MKCoordinateRegion) -> UIImage? {
        images[Self.key(choice, region)]
    }

    func load(_ choice: MapStyleChoice, region: MKCoordinateRegion, size: CGSize) {
        let key = Self.key(choice, region)
        guard images[key] == nil, !inFlight.contains(key) else { return }
        inFlight.insert(key)
        let center = region.center
        let span = region.span
        Task.detached(priority: .userInitiated) {
            let image = try? await Self.render(choice, center: center, span: span, size: size)
            await MainActor.run {
                self.inFlight.remove(key)
                if let image { self.images[key] = image }
            }
        }
    }

    nonisolated private static func render(
        _ choice: MapStyleChoice, center: CLLocationCoordinate2D, span: MKCoordinateSpan, size: CGSize
    ) async throws -> UIImage {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, span: span)
        options.size = size
        options.preferredConfiguration = choice.configuration
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        let snapshot = try await MKMapSnapshotter(options: options).start()
        return snapshot.image
    }

    /// Three decimals of centre and span: the same block at the same zoom shares a picture.
    private static func key(_ choice: MapStyleChoice, _ region: MKCoordinateRegion) -> String {
        String(
            format: "%@|%.3f,%.3f|%.3f,%.3f",
            choice.rawValue, region.center.latitude, region.center.longitude,
            region.span.latitudeDelta, region.span.longitudeDelta
        )
    }
}
