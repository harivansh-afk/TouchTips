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
    typealias Lookup = @MainActor (Double, Double) async throws -> PlaceName

    private let database: AppDatabase
    private let lookup: Lookup
    private let spacing: Duration
    private let throttlePause: Duration
    private var drain: Task<Void, Never>?
    private var rerunRequested = false
    private(set) var isDraining = false

    init(
        database: AppDatabase,
        spacing: Duration = .seconds(1.6),
        throttlePause: Duration = .seconds(60),
        lookup: Lookup? = nil
    ) {
        self.database = database
        self.spacing = spacing
        self.throttlePause = throttlePause
        self.lookup = lookup ?? Self.reverseGeocode
    }

    /// Name every unnamed place that has a meeting. Cheap to call after any write.
    @discardableResult
    func kick() -> Task<Void, Never> {
        if let drain {
            rerunRequested = true
            return drain
        }
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            defer {
                self.drain = nil
                self.rerunRequested = false
            }
            repeat {
                // Coalesce external kicks during a request into one fresh queue pass.
                // Failures alone never request another pass.
                self.rerunRequested = false
                await self.drainQueue()
            } while self.rerunRequested && !Task.isCancelled
        }
        drain = task
        return task
    }

    private func drainQueue() async {
        isDraining = true
        defer { isDraining = false }
        var retriedThrottle = false
        var deferredPlaces: [Int64] = []

        while !Task.isCancelled {
            let next: Place?
            do {
                let deferredIDs = deferredPlaces
                next = try await database.reader.read { db in
                    try Place.awaitingName(limit: 1)
                        .filter(!deferredIDs.contains(Place.Columns.id))
                        .fetchOne(db)
                }
            } catch {
                Log.geocode.error("queue read failed: \(error.localizedDescription)")
                return
            }
            guard let place = next, let placeID = place.id else { return }

            var name: PlaceName?
            var completed = true
            do {
                try Task.checkCancellation()
                name = try await lookup(place.latitude, place.longitude)
                try Task.checkCancellation()
            } catch is CancellationError {
                return
            } catch let error as MKError where error.code == .loadingThrottled {
                // One delayed retry per drain. A persistent throttle stays queued for a later kick.
                guard !retriedThrottle else { return }
                retriedThrottle = true
                Log.geocode.notice("throttled, pausing")
                do {
                    try await Task.sleep(for: throttlePause)
                } catch {
                    return
                }
                continue
            } catch let error as GeocodeError {
                // A completed lookup with no result, or an invalid coordinate, is final.
                Log.geocode.notice("no name for \(place.key): \(error.localizedDescription)")
            } catch let error as MKError where error.code == .placemarkNotFound {
                Log.geocode.notice("no name for \(place.key): \(error.localizedDescription)")
            } catch {
                // Network/service failures must not permanently mark the place as processed.
                Log.geocode.notice("name lookup deferred for \(place.key): \(error.localizedDescription)")
                deferredPlaces.append(placeID)
                completed = false
            }

            guard !Task.isCancelled else { return }
            let title = name?.title
            do {
                if completed {
                    _ = try await database.writer.write { db in
                        // A user may have supplied a name while the network request was suspended.
                        try Place.filter(key: placeID)
                            .filter(Place.Columns.name == nil && Place.Columns.namedAt == nil)
                            .updateAll(
                                db,
                                Place.Columns.name.set(to: title),
                                Place.Columns.namedAt.set(to: Date())
                            )
                    }
                }
            } catch {
                Log.geocode.error("could not store name: \(error.localizedDescription)")
                return
            }
            do {
                try await Task.sleep(for: spacing)
            } catch {
                return
            }
        }
    }

    enum GeocodeError: Error {
        case invalidLocation
        case noResult
    }

    /// One reverse geocode. Also used by the Add sheet for "you are here". Main actor on purpose: MapKit
    /// starts the request through UIKit and asserts when that happens off the main thread.
    static func reverseGeocode(latitude: Double, longitude: Double) async throws -> PlaceName {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { throw GeocodeError.invalidLocation }
        guard let item = try await request.mapItems.first else { throw GeocodeError.noResult }
        return placeName(for: item)
    }

    private static func placeName(for item: MKMapItem) -> PlaceName {
        let detail = item.addressRepresentations?.cityWithContext
        let title = item.name ?? item.address?.shortAddress ?? detail ?? "Unnamed place"
        return PlaceName(title: title, detail: detail)
    }
}
