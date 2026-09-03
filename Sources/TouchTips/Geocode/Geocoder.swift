import CoreLocation
import MapKit
import Observation
import TouchTipsCore

struct PlaceName: Sendable {
    var title: String
    var detail: String?
}

/// Names places lazily. MapKit throttles around fifty requests a minute, so this drains one at a time.
@MainActor
@Observable
final class Geocoder {
    private let database: AppDatabase
    private var drain: Task<Void, Never>?
    private(set) var isDraining = false

    private static let spacing: Duration = .seconds(1.6)
    private static let throttlePause: Duration = .seconds(60)

    init(database: AppDatabase) {
        self.database = database
    }

    /// Name every unnamed place that has a meeting. Cheap to call after any write.
    func kick() {
        guard drain == nil else { return }
        drain = Task { [weak self] in
            await self?.drainQueue()
            self?.drain = nil
        }
    }

    private func drainQueue() async {
        isDraining = true
        defer { isDraining = false }

        while !Task.isCancelled {
            let next: Place?
            do {
                next = try await database.reader.read { db in try Place.awaitingName(limit: 1).fetchOne(db) }
            } catch {
                Log.geocode.error("queue read failed: \(error.localizedDescription)")
                return
            }
            guard let place = next, let placeID = place.id else { return }

            var name: PlaceName?
            do {
                name = try await Self.reverseGeocode(latitude: place.latitude, longitude: place.longitude)
            } catch let error as MKError where error.code == .loadingThrottled {
                Log.geocode.notice("throttled, pausing")
                try? await Task.sleep(for: Self.throttlePause)
                continue
            } catch {
                Log.geocode.notice("no name for \(place.key): \(error.localizedDescription)")
            }

            do {
                try await database.writer.write { db in
                    try Place.filter(key: placeID).updateAll(
                        db,
                        Place.Columns.name.set(to: name?.title),
                        Place.Columns.namedAt.set(to: Date())
                    )
                }
            } catch {
                Log.geocode.error("could not store name: \(error.localizedDescription)")
                return
            }
            try? await Task.sleep(for: Self.spacing)
        }
    }

    enum GeocodeError: Error {
        case invalidLocation
        case noResult
    }

    /// One reverse geocode. Also used by the Add sheet for "you are here".
    nonisolated static func reverseGeocode(latitude: Double, longitude: Double) async throws -> PlaceName {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { throw GeocodeError.invalidLocation }
        let items: [MKMapItem] = try await withCheckedThrowingContinuation { continuation in
            request.getMapItems { items, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: items ?? [])
                }
            }
        }
        guard let item = items.first else { throw GeocodeError.noResult }
        let detail = item.addressRepresentations?.cityWithContext
        let title = item.name ?? item.address?.shortAddress ?? detail ?? "Unnamed place"
        return PlaceName(title: title, detail: detail)
    }
}
