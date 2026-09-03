import Observation
import SwiftUI

enum AppTab: Int, CaseIterable, Identifiable, Hashable {
    case people, map, search

    var id: Int { rawValue }
}

/// Every screen that can be pushed. The view for each lives in `Destination+View.swift`.
enum Destination: Hashable {
    case person(String)
    /// Everyone saved before touchtips, as its own list.
    case undocumented
}

/// One path per tab, the way phia does it. "Inside a page" is nothing more than the selected
/// tab's path being non-empty; pushed screens append to it and never talk to the shell.
@MainActor
@Observable
final class Router {
    var selectedTab: AppTab = .people
    var paths: [AppTab: [Destination]] = [:]
    /// Bumped when the current tab is tapped while already at its root. Roots scroll to top on it.
    var scrollToTop: [AppTab: Int] = [:]
    /// A place the map should centre on and select the next time it looks. Consumed by MapScreen.
    var pendingPlace: Int64?
    /// Bumped every time the search button is tapped. The search tab shows its field and the keyboard on it.
    var searchRequests = 0

    /// Where a person was opened from, when it was not the People tab. Back returns there.
    private var returnTab: AppTab?
    /// The place whose sheet was open at the time, so the map can put it back.
    private var returnPlace: Int64?

    var isOnRoot: Bool { paths[selectedTab, default: []].isEmpty }

    func navigate(to destination: Destination) {
        paths[selectedTab, default: []].append(destination)
    }

    /// The person screen lives on the People tab only. From any other tab this switches there,
    /// pushes, and remembers the way back.
    func open(person contactID: String, fromPlace placeID: Int64? = nil) {
        if selectedTab != .people {
            returnTab = selectedTab
            returnPlace = placeID
            selectedTab = .people
        }
        paths[.people, default: []].append(.person(contactID))
    }

    func back() {
        setPath(Array(paths[selectedTab, default: []].dropLast()), for: selectedTab)
    }

    /// Tap on the tab you are already on: pop to its root, or scroll to top if already there.
    func reselect() {
        if isOnRoot {
            scrollToTop[selectedTab, default: 0] += 1
        } else {
            setPath([], for: selectedTab)
        }
    }

    /// Jump to the map with this place selected.
    func showPlace(_ placeID: Int64) {
        pendingPlace = placeID
        selectedTab = .map
    }

    func path(for tab: AppTab) -> Binding<[Destination]> {
        Binding(
            get: { self.paths[tab, default: []] },
            set: { self.setPath($0, for: tab) }
        )
    }

    /// Every pop goes through here, the swipe included, so returning to the origin tab is consistent.
    private func setPath(_ path: [Destination], for tab: AppTab) {
        paths[tab] = path
        guard path.isEmpty, tab == .people, let returnTab else { return }
        self.returnTab = nil
        pendingPlace = returnPlace
        returnPlace = nil
        selectedTab = returnTab
    }
}
