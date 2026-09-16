import CoreLocation

/// Location is optional and used only for explicit foreground place capture.
enum LocationPermissionAction {
    case request, openSettings, allowed

    init(status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .request
        case .authorizedAlways, .authorizedWhenInUse: self = .allowed
        default: self = .openSettings
        }
    }

    static let backgroundExplanation = "Location is optional. Add a place while using TouchTips."
}
