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

    var isOnRoot: Bool { paths[selectedTab, default: []].isEmpty }

    func navigate(to destination: Destination) {
        paths[selectedTab, default: []].append(destination)
    }

    func back() {
        _ = paths[selectedTab, default: []].popLast()
    }

    /// Tap on the tab you are already on: pop to its root, or scroll to top if already there.
    func reselect() {
        if isOnRoot {
            scrollToTop[selectedTab, default: 0] += 1
        } else {
            paths[selectedTab] = []
        }
    }

    func path(for tab: AppTab) -> Binding<[Destination]> {
        Binding(
            get: { self.paths[tab, default: []] },
            set: { self.paths[tab] = $0 }
        )
    }
}
