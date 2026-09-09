import CoreLocation
@testable import TouchTips
import XCTest

@MainActor
final class CapturePresenceTests: XCTestCase {
    func testArbitraryBackgroundLaunchDefersStandardRequestUntilForeground() {
        let manager = PresenceManagerProbe()
        let presence = CapturePresence(manager: manager)
        presence.update(enabled: true, applicationState: .background)
        presence.update(enabled: true, applicationState: .inactive)
        XCTAssertEqual(manager.starts, 0)

        presence.update(enabled: true, applicationState: .active)
        XCTAssertEqual(manager.starts, 1)
        XCTAssertTrue(manager.showsBackgroundLocationIndicator)
        XCTAssertTrue(manager.allowsBackgroundLocationUpdates)
        XCTAssertFalse(manager.pausesLocationUpdatesAutomatically)
        XCTAssertEqual(manager.desiredAccuracy, kCLLocationAccuracyThreeKilometers)
    }

    func testOnlySignificantChangeWakeCanEstablishSessionInBackground() {
        let manager = PresenceManagerProbe()
        let presence = CapturePresence(manager: manager)
        presence.update(enabled: true, applicationState: .background)
        XCTAssertEqual(manager.starts, 0)
        presence.update(enabled: true, applicationState: .background, significantChangeWake: true)
        XCTAssertEqual(manager.starts, 1)
        // Later standard callbacks do not restart the session on every location delivery.
        presence.update(enabled: true, applicationState: .background)
        XCTAssertEqual(manager.starts, 1)
    }

    func testForegroundReassertsAnExistingSessionWithoutStoppingIt() {
        let manager = PresenceManagerProbe()
        let presence = CapturePresence(manager: manager)
        presence.update(enabled: true, applicationState: .active)
        presence.update(enabled: true, applicationState: .background)
        presence.update(enabled: true, applicationState: .active, restart: true)
        XCTAssertEqual(manager.starts, 2)
        XCTAssertEqual(manager.stops, 0)
    }

    func testDisablingStopsSessionAndLaterBackgroundUseCannotRestartIt() {
        let manager = PresenceManagerProbe()
        let presence = CapturePresence(manager: manager)
        presence.update(enabled: true, applicationState: .active)
        presence.update(enabled: false, applicationState: .background)
        presence.update(enabled: false, applicationState: .background, significantChangeWake: true)
        XCTAssertEqual(manager.stops, 1)
        XCTAssertFalse(manager.allowsBackgroundLocationUpdates)
        presence.update(enabled: true, applicationState: .background)
        XCTAssertEqual(manager.starts, 1)
        presence.update(enabled: true, applicationState: .active)
        XCTAssertEqual(manager.starts, 2)
    }
}

private final class PresenceManagerProbe: CLLocationManager {
    private(set) var starts = 0
    private(set) var stops = 0

    override func startUpdatingLocation() {
        starts += 1
    }

    override func stopUpdatingLocation() {
        stops += 1
    }
}
