import MapKit
import SwiftUI

/// The four ways to draw the map. Points of interest stay off in all of them: the app's own pins
/// are the points of interest. Elevation stays flat: the map is a reference, not a flyover.
/// Muted is monotone: MapKit's muted dark under a grayscale filter. The pins are drawn over the
/// filter, not under it, so they keep their tint.
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

    /// What marks a place: a quiet blue against the monotone map, white against colour.
    var placeTint: Color {
        self == .muted ? .placed : .white
    }

    /// The filter Muted runs over the map layer. It costs a re-render of that layer per frame, so
    /// the three colour styles run none.
    var grayscale: Double {
        self == .muted ? 1 : 0
    }

    /// The shipped picture of this style. Rendered once with MKMapSnapshotter on a Mac; the Muted
    /// one is grayscaled in the file so no filter runs in the sheet.
    var preview: ImageResource {
        switch self {
        case .muted: .mapMuted
        case .standard: .mapStandard
        case .satellite: .mapSatellite
        case .hybrid: .mapHybrid
        }
    }
}
