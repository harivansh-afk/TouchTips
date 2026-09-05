import CoreLocation

/// When In Use also covers Allow Once and a declined Always upgrade. Neither can reliably
/// show another authorization prompt, so settings are the recovery path for all three.
enum LocationPermissionAction {
    case request, openSettings, allowed

    init(status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .request
        case .authorizedAlways: self = .allowed
        default: self = .openSettings
        }
    }

    static let backgroundExplanation = "Choose Always in Settings to capture places in the background."
}
