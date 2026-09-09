import CoreLocation
@testable import TouchTips
import XCTest

@MainActor
final class CaptureFenceTests: XCTestCase {
    func testReleasingFenceCancelsObservationAndAuthorizationSession() async {
        let probe = FenceProbe()
        var fence: CaptureFence? = probe.fence()
        let isReleased = { [weak fence] in fence == nil }
        fence?.configure(authorized: true, protectedDataAvailable: true)
        await eventually { probe.activeObservations == 1 }
        fence = nil
        await eventually { isReleased() && probe.activeObservations == 0 }
        XCTAssertEqual(probe.calls.filter { $0 == "invalidate" }.count, 1)
        probe.emit?()
        XCTAssertEqual(probe.wakes, 0)
    }

    func testAuthorizationPrecedesOpeningAndProtectedDataDefersOpening() async {
        let probe = FenceProbe()
        let fence = probe.fence()
        fence.configure(authorized: false, protectedDataAvailable: true)
        XCTAssertTrue(probe.calls.isEmpty)
        fence.configure(authorized: true, protectedDataAvailable: false)
        XCTAssertEqual(probe.calls, ["authorize"])
        fence.configure(authorized: true, protectedDataAvailable: true)
        await eventually { probe.observations == 1 }
        fence.configure(authorized: true, protectedDataAvailable: true)
        XCTAssertEqual(probe.calls, ["authorize", "open", "observe"])
        fence.configure(authorized: false, protectedDataAvailable: true)
        await eventually { probe.activeObservations == 0 }
        XCTAssertEqual(probe.calls.filter { $0 == "invalidate" }.count, 1)
    }

    func testPermissionRestoredDuringCancellationReusesOneMonitorAndOneObserver() async {
        let probe = FenceProbe()
        let fence = probe.fence()
        fence.configure(authorized: true, protectedDataAvailable: true)
        await eventually { probe.activeObservations == 1 }
        fence.configure(authorized: false, protectedDataAvailable: true)
        fence.configure(authorized: true, protectedDataAvailable: true)
        await eventually { probe.observations == 2 }
        XCTAssertEqual(probe.calls.filter { $0 == "open" }.count, 1)
        XCTAssertEqual(probe.maximumObservers, 1)
        fence.configure(authorized: false, protectedDataAvailable: true)
        await eventually { probe.activeObservations == 0 }
    }

    func testLocationArrivingBeforeMonitorOpensIsNotLost() async {
        let probe = FenceProbe()
        var opening: CheckedContinuation<CaptureFenceMonitor, Never>?
        let fence = CaptureFence(beginSession: { {} }, connect: {
            await withCheckedContinuation { opening = $0 }
        }, wake: {})
        fence.configure(authorized: true, protectedDataAvailable: true)
        await eventually { opening != nil }
        fence.update(fix(latitude: 1))
        fence.update(fix(latitude: 2))
        opening?.resume(returning: probe.monitor)
        await eventually { probe.replacements.count == 1 }
        XCTAssertEqual(probe.replacements.first?.coordinate.latitude, 2)
        fence.configure(authorized: false, protectedDataAvailable: true)
        await eventually { probe.activeObservations == 0 }
    }

    func testPersistedFenceSurvivesNearbyFixesWithoutRearming() async {
        let probe = FenceProbe()
        probe.storedCenter = fix(latitude: 1)
        let fence = probe.fence()
        fence.configure(authorized: true, protectedDataAvailable: true)
        fence.update(fix(latitude: 1.0001))
        await eventually { probe.reads > 0 }
        XCTAssertTrue(probe.replacements.isEmpty)
        XCTAssertEqual(probe.removals, 0)
        fence.update(fix(latitude: 1.002))
        await eventually { probe.replacements.count == 1 }
        XCTAssertEqual(probe.removals, 0, "Replacing a condition must not remove the old record first")
        fence.configure(authorized: false, protectedDataAvailable: true)
        await eventually { probe.activeObservations == 0 }
    }

    func testCoarseStaleInvalidAndOutOfOrderFixesCannotMoveFence() async {
        let probe = FenceProbe()
        let fence = probe.fence()
        fence.configure(authorized: true, protectedDataAvailable: true)
        let now = Date()
        fence.update(fix(latitude: 1, accuracy: 3000), now: now)
        fence.update(fix(latitude: 2, at: now.addingTimeInterval(-300)), now: now)
        fence.update(fix(latitude: 91), now: now)
        fence.update(fix(latitude: 3, accuracy: -1), now: now)
        fence.update(fix(latitude: 4, at: now), now: now)
        await eventually { probe.replacements.count == 1 }
        fence.update(fix(latitude: 5, at: now.addingTimeInterval(-1)), now: now)
        await Task.yield()
        XCTAssertEqual(probe.replacements.map(\.coordinate.latitude), [4])
        fence.configure(authorized: false, protectedDataAvailable: true)
        await eventually { probe.activeObservations == 0 }
    }

    func testResetWaitsForBlockedReplacementThenRemovesIt() async {
        let probe = FenceProbe()
        var replacement: CheckedContinuation<Void, Never>?
        probe.beforeReplace = { await withCheckedContinuation { replacement = $0 } }
        let fence = probe.fence()
        fence.configure(authorized: true, protectedDataAvailable: true)
        fence.update(fix(latitude: 1))
        await eventually { replacement != nil }
        var resetFinished = false
        let reset = Task { await fence.reset(); resetFinished = true }
        await Task.yield()
        XCTAssertFalse(resetFinished)
        replacement?.resume()
        await reset.value
        XCTAssertNil(probe.storedCenter)
        XCTAssertEqual(probe.removals, 1)
        XCTAssertEqual(probe.calls.suffix(2), ["replace", "remove"])
        fence.configure(authorized: false, protectedDataAvailable: true)
        await eventually { probe.activeObservations == 0 }
    }

    func testNewFixSupersedesAnOlderFixWhoseRecordReadIsBlocked() async {
        let probe = FenceProbe()
        var read: CheckedContinuation<Void, Never>?
        probe.beforeRead = {
            probe.beforeRead = nil
            await withCheckedContinuation { read = $0 }
        }
        let fence = probe.fence()
        fence.configure(authorized: true, protectedDataAvailable: true)
        fence.update(fix(latitude: 1))
        await eventually { read != nil }
        fence.update(fix(latitude: 2))
        read?.resume()
        await eventually { probe.replacements.count == 1 }
        XCTAssertEqual(probe.replacements.map(\.coordinate.latitude), [2])
        fence.configure(authorized: false, protectedDataAvailable: true)
        await eventually { probe.activeObservations == 0 }
    }

    func testRevokedAuthorizationCannotWriteAfterBlockedRecordRead() async {
        let probe = FenceProbe()
        var read: CheckedContinuation<Void, Never>?
        probe.beforeRead = { await withCheckedContinuation { read = $0 } }
        let fence = probe.fence()
        fence.configure(authorized: true, protectedDataAvailable: true)
        fence.update(fix(latitude: 1))
        await eventually { read != nil }
        fence.configure(authorized: false, protectedDataAvailable: true)
        read?.resume()
        await eventually { probe.activeObservations == 0 }
        XCTAssertTrue(probe.replacements.isEmpty)
    }

    func testFailedObservationRecoversOnNextWakeWithoutPollingOrReopening() async {
        let probe = FenceProbe()
        probe.failNextObservation = true
        let fence = probe.fence()
        fence.configure(authorized: true, protectedDataAvailable: true)
        await eventually { probe.observations == 1 }
        await Task.yield()
        XCTAssertEqual(probe.observations, 1)
        fence.configure(authorized: true, protectedDataAvailable: true)
        await eventually { probe.observations == 2 }
        XCTAssertEqual(probe.calls.filter { $0 == "open" }.count, 1)
        probe.emit?()
        XCTAssertEqual(probe.wakes, 1)
        fence.configure(authorized: false, protectedDataAvailable: true)
        probe.emit?()
        XCTAssertEqual(probe.wakes, 1, "A queued event after permission loss must not start capture")
        await eventually { probe.activeObservations == 0 }
    }

    func testProtectedDataLossDuringReadDefersWriteUntilAvailable() async {
        let probe = FenceProbe()
        var read: CheckedContinuation<Void, Never>?
        probe.beforeRead = {
            probe.beforeRead = nil
            await withCheckedContinuation { read = $0 }
        }
        let fence = probe.fence()
        fence.configure(authorized: true, protectedDataAvailable: true)
        fence.update(fix(latitude: 1))
        await eventually { read != nil }
        fence.configure(authorized: true, protectedDataAvailable: false)
        read?.resume()
        await eventually { probe.activeObservations == 0 }
        XCTAssertTrue(probe.replacements.isEmpty)
        probe.emit?()
        XCTAssertEqual(probe.wakes, 0)
        fence.configure(authorized: true, protectedDataAvailable: true)
        await eventually { probe.replacements.count == 1 }
        XCTAssertEqual(probe.calls.filter { $0 == "open" }.count, 1)
        fence.configure(authorized: false, protectedDataAvailable: true)
        await eventually { probe.activeObservations == 0 }
    }

    private func fix(latitude: Double, accuracy: Double = 10, at date: Date = .now) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: 0),
            altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: date
        )
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0 ..< 200 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Condition did not complete", file: file, line: line)
    }
}

@MainActor
private final class FenceProbe {
    var calls: [String] = []
    var storedCenter: CLLocation?
    var replacements: [CLLocation] = []
    var removals = 0
    var reads = 0
    var observations = 0
    var activeObservations = 0
    var maximumObservers = 0
    var wakes = 0
    var failNextObservation = false
    var beforeReplace: (() async -> Void)?
    var beforeRead: (() async -> Void)?
    var emit: (() -> Void)?

    func fence() -> CaptureFence {
        CaptureFence(beginSession: {
            self.calls.append("authorize")
            return { self.calls.append("invalidate") }
        }, connect: {
            self.calls.append("open")
            return self.monitor
        }, wake: { self.wakes += 1 })
    }

    var monitor: CaptureFenceMonitor {
        CaptureFenceMonitor(center: {
            self.reads += 1
            await self.beforeRead?()
            return self.storedCenter
        }, replace: { location in
            await self.beforeReplace?()
            self.calls.append("replace")
            self.storedCenter = location
            self.replacements.append(location)
        }, remove: {
            self.calls.append("remove")
            self.storedCenter = nil
            self.removals += 1
        }, observe: { emit in
            self.calls.append("observe")
            self.observations += 1
            if self.failNextObservation {
                self.failNextObservation = false
                throw CocoaError(.fileReadUnknown)
            }
            self.emit = emit
            self.activeObservations += 1
            self.maximumObservers = max(self.maximumObservers, self.activeObservations)
            defer { self.activeObservations -= 1 }
            // A cancellable stand-in for waiting on Core Location's async event iterator.
            try await Task.sleep(for: .seconds(60))
        })
    }
}
