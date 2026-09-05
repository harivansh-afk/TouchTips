import Foundation

/// When the process stays resident. Always by default; the Settings sheet can narrow it.
enum PresencePolicy: String, CaseIterable, Identifiable {
    case always
    /// Only while CoreLocation says we are at a place.
    case atPlaces
    case off

    static let key = "presence"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .always: "Always"
        case .atPlaces: "At places"
        case .off: "Off"
        }
    }

    static var stored: PresencePolicy {
        UserDefaults.standard.string(forKey: key).flatMap(PresencePolicy.init) ?? .always
    }
}
