import Observation
import SwiftUI

enum AppTab: Int, CaseIterable, Identifiable, Hashable {
    case people, map, search

    var id: Int { rawValue }
}

/// Every screen that can be pushed. The view for each lives in `Destination+View.swift`.
enum Destination: Hashable {
    case person(String)
    /// Everyone saved before TouchedTips, as its own list.
    case undocumented
}

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

    var isOnRoot: Bool { paths[selectedTab, default: []].isEmpty }

    func navigate(to destination: Destination) {
        paths[selectedTab, default: []].append(destination)
    }

    /// The person screen is one screen, pushed on whichever tab you are on, so back is one pop
    /// and lands where you came from.
    func open(person contactID: String) {
        paths[selectedTab, default: []].append(.person(contactID))
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

    /// Every pop goes through here, the swipe included.
    private func setPath(_ path: [Destination], for tab: AppTab) {
        paths[tab] = path
    }
}
