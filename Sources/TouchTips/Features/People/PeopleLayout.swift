import SwiftUI

/// How the People tab lays everyone out. Chosen in Settings and remembered; the search tab keeps
/// the default, since a search result is a list whatever the home looks like.
enum PeopleLayout: String, CaseIterable, Identifiable {
    /// Newest first, grouped by month. What the tab has always shown.
    case byDate = "default"
    /// One line down the left with a dot per person. Months are ticks on it and a quiet stretch is named.
    case timeline
    /// Grouped by where, the place with the newest meeting first.
    case byPlace = "location"

    static let key = "peopleLayout"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .byDate: "Default"
        case .timeline: "Timeline"
        case .byPlace: "Location"
        }
    }

    /// One line under the picker saying what the chosen layout does.
    var detail: String {
        switch self {
        case .byDate: "Newest first, grouped by month."
        case .timeline: "Meetings along a timeline."
        case .byPlace: "Grouped by place, newest first."
        }
    }
}
