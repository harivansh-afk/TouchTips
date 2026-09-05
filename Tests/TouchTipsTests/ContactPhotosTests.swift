import SwiftUI
@testable import TouchTips
import TouchTipsCore
import XCTest

@MainActor
final class ContactPhotosTests: XCTestCase {
    func testVisibleAvatarReloadsAfterCacheReset() async throws {
        let firstLoaded = expectation(description: "Initial avatar")
        let reloaded = expectation(description: "Visible avatar reloaded")
        let first = try thumbnail(.red)
        let second = try thumbnail(.blue)
        var requests = 0
        let photos = ContactPhotos { _ in
            requests += 1
            if requests == 1 {
                firstLoaded.fulfill()
                return first
            }
            reloaded.fulfill()
            return second
        }
        let app = try AppModel(database: AppDatabase.inMemory(), photos: photos)
        let host = UIHostingController(rootView: ContactAvatar(contactID: "a", initials: "A").environment(app))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()

        await fulfillment(of: [firstLoaded], timeout: 2)
        XCTAssertEqual(photos.image(for: "a")?.pngData(), UIImage(data: first)?.pngData())
        let loadID = photos.loadID(for: "a")
        photos.reset()
        XCTAssertNotEqual(photos.loadID(for: "a"), loadID)
        await fulfillment(of: [reloaded], timeout: 2)
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(photos.image(for: "a")?.pngData(), UIImage(data: second)?.pngData())
    }

    func testMapReloadsPhotosWithoutAPlaceChange() async throws {
        let firstLoaded = expectation(description: "Initial map photo")
        let reloaded = expectation(description: "Map photo reloaded")
        let data = try thumbnail(.blue)
        var requests = 0
        let photos = ContactPhotos { _ in
            requests += 1
            if requests == 1 {
                firstLoaded.fulfill()
            } else {
                reloaded.fulfill()
            }
            return data
        }
        let database = try AppDatabase.inMemory()
        let place = try database.writer.write { db in
            try Place.findOrCreate(db, key: "test-map-photo", latitude: 38, longitude: -78, name: "Cafe")
        }
        try Ingest.addExact(contactID: "a", name: "Alice", at: .now, placeID: place.id, to: database)
        let app = AppModel(database: database, photos: photos)
        let host = UIHostingController(rootView: MapScreen().environment(app).environment(Router()))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 200, height: 400)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()

        await fulfillment(of: [firstLoaded], timeout: 2)
        photos.reset()
        await fulfillment(of: [reloaded], timeout: 2)
        XCTAssertEqual(requests, 2)
        XCTAssertNotNil(photos.image(for: "a"))
    }

    func testOldFetchCannotOverwriteNewPhotoAfterReset() async throws {
        let fetches = PendingThumbnails()
        let photos = ContactPhotos(fetch: fetches.fetch)
        let oldStarted = expectation(description: "Old request")
        fetches.onRequest = { oldStarted.fulfill() }
        let old = Task { await photos.load("a") }
        await fulfillment(of: [oldStarted], timeout: 2)

        photos.reset()
        let newStarted = expectation(description: "New request")
        fetches.onRequest = { newStarted.fulfill() }
        let fresh = Task { await photos.load("a") }
        await fulfillment(of: [newStarted], timeout: 2)
        guard fetches.count == 2 else {
            fetches.finish(0, with: nil)
            await old.value
            await fresh.value
            return
        }
        let second = try thumbnail(.blue)
        fetches.finish(1, with: second)
        await fresh.value
        try fetches.finish(0, with: thumbnail(.red))
        await old.value
        XCTAssertEqual(photos.image(for: "a")?.pngData(), UIImage(data: second)?.pngData())
    }

    func testMissingPhotoIsRetriedAfterReset() async throws {
        let photo = try thumbnail(.blue)
        var requests = 0
        let photos = ContactPhotos { _ in
            requests += 1
            return requests == 1 ? nil : photo
        }
        await photos.load("a")
        await photos.load("a")
        XCTAssertEqual(requests, 1)
        XCTAssertNil(photos.image(for: "a"))
        photos.reset()
        await photos.load("a")
        XCTAssertEqual(requests, 2)
        XCTAssertNotNil(photos.image(for: "a"))
    }

    private func thumbnail(_ color: UIColor) throws -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 2, height: 2)
        let image = UIGraphicsImageRenderer(size: bounds.size).image { context in
            color.setFill()
            context.fill(bounds)
        }
        return try XCTUnwrap(image.pngData())
    }
}

@MainActor
private final class PendingThumbnails {
    var onRequest: (() -> Void)?
    private var pending: [CheckedContinuation<Data?, Never>?] = []

    var count: Int {
        pending.count
    }

    func fetch(_ contactID: String) async -> Data? {
        await withCheckedContinuation { continuation in
            pending.append(continuation)
            onRequest?()
        }
    }

    func finish(_ index: Int, with data: Data?) {
        guard pending.indices.contains(index) else {
            XCTFail("Thumbnail request \(index) did not start")
            return
        }
        pending[index]?.resume(returning: data)
        pending[index] = nil
    }
}
