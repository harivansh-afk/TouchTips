import MapKit
import SwiftUI

/// The four ways to draw the map. Points of interest stay off in all of them: the app's own pins
/// are the points of interest. Elevation stays flat: the map is a reference, not a flyover.
/// Muted is MapKit's own muted dark, no filter over it: a filter would take the colour out of the
/// pins too, and the pins are the one thing on that map allowed a colour.
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

    /// What marks a place: a quiet green against the near-monotone map, white against colour.
    var placeTint: Color {
        self == .muted ? .placed : .white
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
