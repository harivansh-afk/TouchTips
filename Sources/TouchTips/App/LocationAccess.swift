import CoreLocation
import Observation

/// While Using location, asked for only when adding a place in TouchTips. Never runs in the background.
@MainActor
@Observable
final class LocationAccess: NSObject, CLLocationManagerDelegate {
    enum Action: Equatable {
        case request, openSettings, allowed

        init(status: CLAuthorizationStatus) {
            switch status {
            case .notDetermined: self = .request
            case .authorizedAlways, .authorizedWhenInUse: self = .allowed
            default: self = .openSettings
            }
        }
    }

    private let manager = CLLocationManager()
    private(set) var status: CLAuthorizationStatus

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var granted: Bool {
        action == .allowed
    }

    var action: Action {
        Action(status: status)
    }

    func request() {
        guard action == .request else { return }
        manager.requestWhenInUseAuthorization()
    }

    func refresh() {
        status = manager.authorizationStatus
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { self.status = status }
    }
}
