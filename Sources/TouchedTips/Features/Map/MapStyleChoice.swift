import MapKit
import SwiftUI

/// The four ways to draw the map. Points of interest stay off in all of them: the app's own pins
/// are the points of interest. Elevation stays flat: the map is a reference, not a flyover.
enum MapStyleChoice: String, CaseIterable, Identifiable {
    case muted, standard, satellite, hybrid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .muted: "Muted"
        case .standard: "Standard"
        case .satellite: "Satellite"
        case .hybrid: "Hybrid"
        }
    }

    var style: MapStyle {
        switch self {
        case .muted: .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false)
        case .standard: .standard(elevation: .flat, emphasis: .automatic, pointsOfInterest: .excludingAll, showsTraffic: false)
        case .satellite: .imagery(elevation: .flat)
        case .hybrid: .hybrid(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false)
        }
    }

    /// The same style for MKMapSnapshotter, which speaks MapKit's older configuration objects.
    var configuration: MKMapConfiguration {
        switch self {
        case .muted:
            let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            config.pointOfInterestFilter = .excludingAll
            return config
        case .standard:
            let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .default)
            config.pointOfInterestFilter = .excludingAll
            return config
        case .satellite:
            return MKImageryMapConfiguration(elevationStyle: .flat)
        case .hybrid:
            let config = MKHybridMapConfiguration(elevationStyle: .flat)
            config.pointOfInterestFilter = .excludingAll
            return config
        }
    }

    /// What a tile shows until its snapshot arrives.
    var ground: Color {
        switch self {
        case .muted: Color(white: 0.10)
        case .standard: Color(white: 0.14)
        case .satellite, .hybrid: Color(red: 0.17, green: 0.19, blue: 0.15)
        }
    }
}
