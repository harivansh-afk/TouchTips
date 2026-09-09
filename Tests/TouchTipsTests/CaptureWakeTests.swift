import CoreLocation
@testable import TouchTips
import TouchTipsCore
import UIKit
import XCTest

@MainActor
final class CaptureWakeTests: XCTestCase {
    func testAssertionStartsBeforeDebounceAndCoalescesWithLaterWake() async throws {
        let probe = BackgroundProbe()
        var reads = 0
        let capture = try makeCapture(probe) { _ in
            reads += 1
            return ContactChangeSet(token: Data([2]))
        }
        capture.scheduleTick(.contacts, after: 0.03)
        XCTAssertEqual(probe.started, 1, "The callback must acquire execution time before returning")
        XCTAssertEqual(reads, 0)
        capture.scheduleTick(.movement, after: 20)
        XCTAssertEqual(probe.started, 1)
        await eventually { probe.ended == 1 }
        XCTAssertEqual(reads, 1)
    }

    func testAssertionCoversRetryWaitAndEndsAfterRecovery() async throws {
        let probe = BackgroundProbe()
        var reads = 0
        let capture = try makeCapture(probe, retryDelays: [.milliseconds(50)]) { _ in
            reads += 1
            if reads == 1 {
                throw CocoaError(.fileReadUnknown)
            }
            return ContactChangeSet(token: Data([2]))
        }
        let work = Task { await capture.tick(.contacts) }
        await eventually { reads == 1 }
        XCTAssertEqual(probe.started, 1)
        XCTAssertEqual(probe.ended, 0, "Retry backoff is part of the same finite capture batch")
        let success = await work.value
        XCTAssertTrue(success)
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(probe.started, 1)
        XCTAssertEqual(probe.ended, 1)
    }

    func testAssertionCoversNotificationSubmission() async throws {
        let probe = BackgroundProbe()
        var submission: CheckedContinuation<Void, Never>?
        let capture = try makeCapture(probe, submit: { _ in
            await withCheckedContinuation { submission = $0 }
        }) { _ in
            ContactChangeSet(added: [.init(contactID: "new", name: "New")], token: Data([2]))
        }
        let work = Task { await capture.tick(.contacts) }
        await eventually { submission != nil }
        XCTAssertEqual(probe.ended, 0)
        submission?.resume()
        let success = await work.value
        XCTAssertTrue(success)
        XCTAssertEqual(probe.ended, 1)
    }

    func testExpirationCancelsDebounceWithoutRenewingAssertion() async throws {
        let probe = BackgroundProbe()
        var reads = 0
        let capture = try makeCapture(probe) { _ in
            reads += 1
            return ContactChangeSet(token: Data([2]))
        }
        capture.scheduleTick(.contacts, after: 0.03)
        probe.expire()
        XCTAssertEqual(probe.ended, 1)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(probe.started, 1)
        capture.scheduleTick(.movement)
        await eventually { probe.ended == 2 }
        XCTAssertEqual(reads, 1, "A later delivered wake may start a fresh batch")
    }

    func testExpirationDropsQueuedWakeWhileCancelledReadUnwinds() async throws {
        let probe = BackgroundProbe()
        var pending: CheckedContinuation<ContactChangeSet, Never>?
        var reads = 0
        let capture = try makeCapture(probe) { _ in
            reads += 1
            if reads == 1 {
                return await withCheckedContinuation { pending = $0 }
            }
            return ContactChangeSet(token: Data([2]))
        }
        let work = Task { await capture.tick(.contacts) }
        await eventually { pending != nil }
        capture.scheduleTick(.movement)
        probe.expire()
        XCTAssertEqual(probe.ended, 1, "Expiration must end the assertion even when Contacts I/O cannot cancel")
        pending?.resume(returning: ContactChangeSet(token: Data([2])))
        let success = await work.value
        XCTAssertFalse(success)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(probe.started, 1, "An expired batch cannot renew itself from an older queued wake")
        capture.scheduleTick(.movement)
        await eventually { probe.ended == 2 }
        XCTAssertEqual(reads, 2)
    }

    func testNewLocationWakeAfterExpirationWaitsForOldReadThenKeepsItsOwnAssertion() async throws {
        let probe = BackgroundProbe()
        var oldRead: CheckedContinuation<ContactChangeSet, Never>?
        var newRead: CheckedContinuation<ContactChangeSet, Never>?
        var tokens: [Data?] = []
        var submitted: [String] = []
        let capture = try makeCapture(probe, submit: { submitted.append($0) }) { token in
            tokens.append(token)
            switch tokens.count {
            case 1:
                return await withCheckedContinuation { oldRead = $0 }
            case 2:
                return await withCheckedContinuation { newRead = $0 }
            default:
                XCTFail("Fresh callbacks should coalesce into one follow-up scan")
                return ContactChangeSet(token: Data([3]))
            }
        }
        let expiredWork = Task { await capture.tick(.contacts) }
        await eventually { oldRead != nil }
        probe.expire()
        XCTAssertEqual(probe.ended, 1)

        let manager = CLLocationManager()
        for _ in 0 ..< 3 {
            capture.locationManager(manager, didUpdateLocations: [fix(at: .now)])
        }
        XCTAssertEqual(probe.started, 2)
        XCTAssertEqual(probe.ended, 1)
        XCTAssertEqual(tokens.count, 1, "The old uncancellable Contacts read must finish before another begins")

        oldRead?.resume(returning: ContactChangeSet(token: Data([2])))
        let oldSucceeded = await expiredWork.value
        XCTAssertFalse(oldSucceeded)
        await eventually { newRead != nil }
        XCTAssertEqual(tokens, [Data([1]), Data([1])], "Expired work must not advance the Contacts cursor")
        XCTAssertEqual(probe.started, 2)
        XCTAssertEqual(probe.ended, 1, "Unwinding the old batch must not release the new wake's assertion")

        newRead?.resume(returning: ContactChangeSet(
            added: [.init(contactID: "new", name: "New")], token: Data([2])
        ))
        await eventually { probe.ended == 2 }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(submitted, ["meet-new"])
        XCTAssertEqual(probe.started, 2)
        XCTAssertEqual(probe.ended, 2)
    }

    func testCancellationAndResetReleaseTheirAssertions() async throws {
        let probe = BackgroundProbe()
        var reading = false
        let capture = try makeCapture(probe) { _ in
            reading = true
            try await Task.sleep(for: .seconds(30))
            return ContactChangeSet(token: Data([2]))
        }
        let work = Task { await capture.tick(.contacts) }
        await eventually { reading }
        work.cancel()
        _ = await work.value
        XCTAssertEqual(probe.ended, 1)

        let resetProbe = BackgroundProbe()
        var reads = 0
        let resetting = try makeCapture(resetProbe) { _ in
            reads += 1
            return ContactChangeSet(token: Data([2]), isSnapshot: true)
        }
        resetting.scheduleTick(.contacts, after: 30)
        try await resetting.reset()
        XCTAssertEqual(reads, 1, "Only the reset baseline may run")
        XCTAssertEqual(resetProbe.started, 2)
        XCTAssertEqual(resetProbe.ended, 2)
    }

    func testEveryLocationWakeScansEvenWithoutAUsableNewCoordinate() async throws {
        let probe = BackgroundProbe()
        var reads = 0
        var submitted: [String] = []
        let capture = try makeCapture(probe, submit: { submitted.append($0) }) { _ in
            reads += 1
            return ContactChangeSet(
                added: [.init(contactID: "contact-\(reads)", name: "New")], token: Data([UInt8(reads + 1)])
            )
        }
        let manager = CLLocationManager()
        let now = Date()
        let updates = [
            [fix(at: now)],
            [fix(at: now.addingTimeInterval(1))],
            [fix(at: now.addingTimeInterval(-60))],
            [fix(at: now, accuracy: -1)],
            [fix(at: now, latitude: 100)],
            [],
        ]
        for (index, locations) in updates.enumerated() {
            capture.locationManager(manager, didUpdateLocations: locations)
            XCTAssertEqual(probe.started, index + 1, "A location callback must immediately protect capture work")
            await eventually { probe.ended == index + 1 }
            XCTAssertEqual(submitted.count, index + 1)
        }
        XCTAssertEqual(reads, updates.count, "A recent scan or unusable coordinate cannot suppress catch-up")
    }

    func testLocationBurstsShareOneAssertionAndOneQueuedFollowup() async throws {
        let probe = BackgroundProbe()
        var pending: CheckedContinuation<ContactChangeSet, Never>?
        var reads = 0
        let capture = try makeCapture(probe) { _ in
            reads += 1
            if reads == 1 {
                return await withCheckedContinuation { pending = $0 }
            }
            return ContactChangeSet(token: Data([3]))
        }
        let manager = CLLocationManager()
        for _ in 0 ..< 10 {
            capture.locationManager(manager, didUpdateLocations: [fix(at: .now)])
        }
        await eventually { pending != nil }
        XCTAssertEqual(reads, 1)
        for _ in 0 ..< 10 {
            capture.locationManager(manager, didUpdateLocations: [fix(at: .now)])
        }
        pending?.resume(returning: ContactChangeSet(token: Data([2])))
        await eventually { probe.ended == 1 }
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(probe.started, 1)
    }

    func testStoppingObservationReleasesScheduledWork() throws {
        let probe = BackgroundProbe()
        let capture = try makeCapture(probe) { _ in
            XCTFail("Cancelled debounce ran")
            return ContactChangeSet(token: Data([2]))
        }
        capture.scheduleTick(.contacts, after: 30)
        capture.stopObservingContacts()
        XCTAssertEqual(probe.started, 1)
        XCTAssertEqual(probe.ended, 1)
    }

    private func makeCapture(
        _ probe: BackgroundProbe,
        retryDelays: [Duration] = [],
        submit: @escaping (String) async -> Void = { _ in },
        changes: @escaping (Data?) async throws -> ContactChangeSet
    ) throws -> CaptureCoordinator {
        let db = try AppDatabase.inMemory()
        try Ingest.apply(ContactChangeSet(token: Data([1])), now: .now, to: db)
        let notifier = Notifier(database: db, delivery: NotificationDelivery(
            authorization: { .authorized }, submittedIDs: { [] }, submit: { await submit($0.identifier) }
        ))
        return CaptureCoordinator(
            database: db, notifier: notifier,
            contacts: CaptureContacts(authorized: { true }, changes: changes),
            location: CaptureLocation(authorized: { false }, fix: { _ in nil }),
            retryDelays: retryDelays, beginBackground: { probe.begin(expiration: $0) }
        )
    }

    private func fix(at date: Date, accuracy: Double = 20, latitude: Double = 37) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: -122),
            altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: date
        )
    }

    private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0 ..< 200 {
            if predicate() {
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Expected capture work to finish", file: file, line: line)
    }
}

@MainActor
private final class BackgroundProbe {
    private(set) var started = 0
    private(set) var ended = 0
    private var expiration: (@MainActor () -> Void)?

    func begin(expiration: @escaping @MainActor () -> Void) -> CaptureBackgroundTask {
        CaptureBackgroundTask(expiration: expiration, begin: { callback in
            started += 1
            self.expiration = callback
            return UIBackgroundTaskIdentifier(rawValue: started)
        }, end: { _ in self.ended += 1 })
    }

    func expire() {
        expiration?()
    }
}
