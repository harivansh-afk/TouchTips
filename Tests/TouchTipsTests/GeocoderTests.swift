import MapKit
@testable import TouchTips
import TouchTipsCore
import XCTest

@MainActor
final class GeocoderTests: XCTestCase {
    func testTransientFailureRetriesOnLaterKick() async throws {
        let database = try AppDatabase.inMemory()
        let place = try seedPlace(in: database)
        var attempts = 0
        let geocoder = Geocoder(database: database, spacing: .zero) { _, _ in
            attempts += 1
            if attempts == 1 {
                throw URLError(.notConnectedToInternet)
            }
            return PlaceName(title: "Recovered cafe")
        }

        await geocoder.kick().value
        let failed = try await database.reader.read { try Place.fetchOne($0, key: place.id)! }
        XCTAssertEqual(attempts, 1, "A transient failure must be deferred instead of spinning")
        XCTAssertNil(failed.name)
        XCTAssertNil(failed.namedAt)

        await geocoder.kick().value
        let recovered = try await database.reader.read { try Place.fetchOne($0, key: place.id)! }
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(recovered.name, "Recovered cafe")
        XCTAssertNotNil(recovered.namedAt)
    }

    func testKickDuringLookupRunsOneFreshPassAfterFailure() async throws {
        for recovers in [true, false] {
            let database = try AppDatabase.inMemory()
            let place = try seedPlace(in: database)
            let (started, signal) = AsyncStream<Void>.makeStream()
            var response: CheckedContinuation<Void, Never>?
            var attempts = 0
            let geocoder = Geocoder(database: database, spacing: .zero) { _, _ in
                attempts += 1
                if attempts == 1 {
                    await withCheckedContinuation {
                        response = $0
                        signal.yield()
                        signal.finish()
                    }
                    throw URLError(.notConnectedToInternet)
                }
                if !recovers {
                    throw URLError(.notConnectedToInternet)
                }
                return PlaceName(title: "Recovered cafe")
            }

            let drain = geocoder.kick()
            for await _ in started {
                break
            }
            // Multiple foreground/ingest signals should coalesce while the lookup is suspended.
            geocoder.kick()
            geocoder.kick()
            response?.resume()
            await drain.value

            let saved = try await database.reader.read { try Place.fetchOne($0, key: place.id)! }
            XCTAssertEqual(attempts, 2, "Only external kicks may request a fresh pass")
            XCTAssertEqual(saved.name, recovers ? "Recovered cafe" : nil)
            XCTAssertEqual(saved.namedAt != nil, recovers)
        }
    }

    func testNameSavedDuringLookupSurvivesSuccessAndNoResult() async throws {
        for noResult in [false, true] {
            let database = try AppDatabase.inMemory()
            let place = try seedPlace(in: database)
            let geocoder = Geocoder(database: database, spacing: .zero) { _, _ in
                // The queue has read an unnamed record. Simulate a user save during its await.
                try await database.writer.write { db in
                    _ = try Place.findOrCreate(
                        db, key: place.key, latitude: place.latitude, longitude: place.longitude,
                        name: "Chosen cafe"
                    )
                }
                if noResult {
                    throw Geocoder.GeocodeError.noResult
                }
                return PlaceName(title: "Generic street address")
            }

            await geocoder.kick().value
            let saved = try await database.reader.read { try Place.fetchOne($0, key: place.id)! }
            XCTAssertEqual(saved.name, "Chosen cafe")
            XCTAssertNotNil(saved.namedAt)
        }
    }

    func testNoResultCompletesPlaceWithoutRetry() async throws {
        let database = try AppDatabase.inMemory()
        let place = try seedPlace(in: database)
        var attempts = 0
        let geocoder = Geocoder(database: database, spacing: .zero) { _, _ in
            attempts += 1
            throw Geocoder.GeocodeError.noResult
        }

        await geocoder.kick().value
        await geocoder.kick().value
        let saved = try await database.reader.read { try Place.fetchOne($0, key: place.id)! }
        XCTAssertEqual(attempts, 1)
        XCTAssertNil(saved.name)
        XCTAssertNotNil(saved.namedAt)
    }

    func testFailingPlaceDoesNotStarveOtherPlaces() async throws {
        let database = try AppDatabase.inMemory()
        let older = try seedPlace(in: database)
        let newer = try await database.writer.write { db in
            try Place.findOrCreate(db, key: "newer", latitude: 40, longitude: -74)
        }
        try Ingest.addExact(contactID: "new-person", name: "New Person", at: .now, placeID: newer.id, to: database)
        var failedAttempts = 0
        let geocoder = Geocoder(database: database, spacing: .zero) { latitude, _ in
            if latitude == newer.latitude {
                failedAttempts += 1
                throw URLError(.timedOut)
            }
            return PlaceName(title: "Older cafe")
        }

        await geocoder.kick().value
        let saved = try await database.reader.read { try Place.fetchOne($0, key: older.id)! }
        let deferred = try await database.reader.read { try Place.fetchOne($0, key: newer.id)! }
        XCTAssertEqual(failedAttempts, 1)
        XCTAssertEqual(saved.name, "Older cafe")
        XCTAssertNil(deferred.namedAt)
    }

    func testPersistentThrottleIsBoundedAndRemainsQueued() async throws {
        let database = try AppDatabase.inMemory()
        let place = try seedPlace(in: database)
        var attempts = 0
        let geocoder = Geocoder(database: database, spacing: .zero, throttlePause: .zero) { _, _ in
            attempts += 1
            throw MKError(.loadingThrottled)
        }

        await geocoder.kick().value
        let saved = try await database.reader.read { try Place.fetchOne($0, key: place.id)! }
        XCTAssertEqual(attempts, 2)
        XCTAssertNil(saved.namedAt)
    }

    func testCancellationLeavesPlaceQueued() async throws {
        let database = try AppDatabase.inMemory()
        let place = try seedPlace(in: database)
        let geocoder = Geocoder(database: database, spacing: .zero) { _, _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return PlaceName(title: "Result delivered after cancellation")
        }

        await geocoder.kick().value
        let saved = try await database.reader.read { try Place.fetchOne($0, key: place.id)! }
        XCTAssertNil(saved.name)
        XCTAssertNil(saved.namedAt)
    }

    private func seedPlace(in database: AppDatabase) throws -> Place {
        let place = try database.writer.write { db in
            try Place.findOrCreate(db, key: "test-place", latitude: 38.03, longitude: -78.48)
        }
        try Ingest.addExact(contactID: "test-person", name: "Test Person", at: .now, placeID: place.id, to: database)
        return place
    }
}
