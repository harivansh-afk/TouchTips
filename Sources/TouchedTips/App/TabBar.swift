import SwiftUI

/// tab has something pushed, the tab capsule, and one separate glass circle on the right for
struct TabBar: View {
    @Environment(Router.self) private var router
    @Namespace private var pill

    static let height: CGFloat = 58
    static let bottomPadding: CGFloat = 24
    /// How far above the bottom safe area content stops, so nothing ends under the capsule.
    fileprivate static let contentInset = height + bottomPadding + 8 - 34

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 12) {
                if !router.isOnRoot {
                    sideButton(.caretLeft, label: "Back") {
                        HapticManager.medium()
                        router.back()
                    }
                    .transition(.blurReplace)
                }
                capsule
                sideButton(.magnifyingGlass, label: "Search", selected: router.selectedTab == .search) {
                    HapticManager.selection()
                    router.selectedTab = .search
                    router.searchRequests += 1
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, Self.bottomPadding)
        .ignoresSafeArea(edges: .bottom)
        .animation(.easeInOut, value: router.isOnRoot)
    }

    /// Back and search share one shape: a capsule the height of the bar, glass button style, so the
    /// whole shape is the target and the two sides of the bar match.
    /// The same clear glass as the capsule, so the three shapes read as one bar. The content shape
    /// makes the whole capsule the target, not just the glyph.
    private func sideButton(_ glyph: ImageResource, label: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(glyph, size: 22)
                .foregroundStyle(.white.opacity(selected ? 1 : 0.85))
                .frame(width: 58, height: Self.height)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.clear.interactive(), in: .capsule)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var capsule: some View {
        GlassEffectContainer {
            HStack(spacing: 0) {
                ForEach([AppTab.people, .map]) { tab in
                    tabButton(tab)
                }
            }
            .animation(.snappy, value: router.selectedTab)
            .glassEffect(.clear.interactive(), in: .capsule)
        }
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let selected = router.selectedTab == tab
        return Button {
            select(tab)
        } label: {
            Image(tab.glyph)
                .renderingMode(.template)
                .foregroundStyle(.white.opacity(selected ? 1 : 0.5))
                .frame(maxWidth: .infinity)
                .frame(height: Self.height)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background {
            if selected {
                Capsule()
                    .fill(Color.pill)
                    .padding(5)
                    .matchedGeometryEffect(id: "pill", in: pill)
            }
        }
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func select(_ tab: AppTab) {
        HapticManager.selection()
        if router.selectedTab == tab {
            router.reselect()
        } else {
            router.selectedTab = tab
        }
    }
}

extension View {
    /// Ends this screen's content above the bar. Every screen says it for itself: an inset on a
    /// container is not seen by the screens a tab pushes, nor by MapKit's bottom-left mark.
    func aboveTabBar() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: TabBar.contentInset)
        }
    }
}

extension AppTab {
    var glyph: ImageResource {
        switch self {
        case .people: .users
        case .map: .mapTrifold
        case .search: .magnifyingGlass
        }
    }

    var label: String {
        switch self {
        case .people: "People"
        case .map: "Map"
        case .search: "Search"
        }
    }
}
