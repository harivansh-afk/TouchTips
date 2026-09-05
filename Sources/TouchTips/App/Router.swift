import Observation
import SwiftUI

enum AppTab: Int, CaseIterable, Identifiable, Hashable {
    case people, map, search

    var id: Int {
        rawValue
    }
}

/// Every screen that can be pushed. The view for each lives in `Destination+View.swift`.
enum Destination: Hashable {
    /// `zoom` is off for a programmatic push, which has no row on screen to zoom out of.
    case person(String, zoom: Bool = true)
    /// Everyone saved before TouchTips, as its own list.
    case undocumented
}

/// tab's path being non-empty; pushed screens append to it and never talk to the shell.
@MainActor
@Observable
final class Router {
    var peopleReady = false
    var notificationRequest = 0

    func openNotification(_ contactID: String) {
        notificationRequest += 1
        selectedTab = .people
        paths[.people] = [.person(contactID, zoom: false)]
    }

    var selectedTab: AppTab = .people {
        didSet { restoreBar() }
    }

    var paths: [AppTab: [Destination]] = [:]
    /// How far the tab bar has shrunk under a scroll, 0 full size to 1 minimised. Written by the
    /// scrolling screen, read by the bar. Any change of screen restores it.
    var barProgress: CGFloat = 0
    /// Bumped when the current tab is tapped while already at its root. Roots scroll to top on it.
    var scrollToTop: [AppTab: Int] = [:]
    /// A place the map should centre on and select the next time it looks. Consumed by MapScreen.
    var pendingPlace: Int64?
    /// Bumped every time the search button is tapped. The search tab shows its field and the keyboard on it.
    var searchRequests = 0

    var isOnRoot: Bool {
        paths[selectedTab, default: []].isEmpty
    }

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
            restoreBar()
        } else {
            setPath([], for: selectedTab)
        }
    }

    /// Jump to the map with this place selected.
    func showPlace(_ placeID: Int64) {
        pendingPlace = placeID
        setPath([], for: .map)
        selectedTab = .map
    }

    /// An explicit search action starts at the search field, not a retained person detail.
    func search() {
        setPath([], for: .search)
        selectedTab = .search
        searchRequests += 1
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
        restoreBar()
    }

    /// Back to full size, with the same spring the snap uses.
    func restoreBar() {
        guard barProgress != 0 else { return }
        withAnimation(.appleMusic) { barProgress = 0 }
    }
}
