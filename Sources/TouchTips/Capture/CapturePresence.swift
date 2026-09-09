import CoreLocation
import UIKit

/// Owns the continuous location request separately from significant-change monitoring.
@MainActor
final class CapturePresence {
    let manager: CLLocationManager
    private var active = false

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
    }

    func update(
        enabled: Bool, applicationState: UIApplication.State,
        restart: Bool = false, significantChangeWake: Bool = false
    ) {
        if enabled {
            guard !active || restart else { return }
            // An arbitrary background launch cannot establish a standard session. Leave it pending
            // so the next foreground use or significant-change wake can start it properly.
            guard applicationState == .active || significantChangeWake else { return }
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
            manager.showsBackgroundLocationIndicator = true
            manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
            manager.distanceFilter = kCLDistanceFilterNone
            manager.activityType = .other
            manager.startUpdatingLocation()
        } else {
            guard active else { return }
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates = false
        }
        active = enabled
        Log.capture.notice("presence \(enabled ? "on" : "off", privacy: .public)")
    }
}
