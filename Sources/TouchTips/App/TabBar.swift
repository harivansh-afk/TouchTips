import SwiftUI

/// The phia bar, laid out the way phia lays it out: a back capsule that enters when the selected
/// tab has something pushed, the tab capsule, and one separate glass circle on the right for
/// search, in phia's add-to-closet slot. The only input is `router.isOnRoot`.
struct TabBar: View {
    @Environment(Router.self) private var router
    @Namespace private var pill

    static let height: CGFloat = 58
    static let bottomPadding: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 12) {
                if !router.isOnRoot {
                    backButton
                        .transition(.blurReplace)
                }
                capsule
                searchButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, Self.bottomPadding)
        .ignoresSafeArea(edges: .bottom)
        .animation(.easeInOut, value: router.isOnRoot)
    }

    /// A capsule the height of the bar, so it reads as part of it and the whole thing is the target.
    private var backButton: some View {
        Button {
            HapticManager.medium()
            router.back()
        } label: {
            Icon(.caretLeft, size: 22)
                .foregroundStyle(.white)
                .frame(width: 44, height: Self.height - 16)
                .contentShape(.capsule)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .accessibilityLabel("Back")
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

    /// Search lives in its own circle, like the system's search tab and phia's trailing slot.
    private var searchButton: some View {
        let selected = router.selectedTab == .search
        return Button {
            select(.search)
        } label: {
            Icon(.magnifyingGlass, size: 22)
                .foregroundStyle(.white.opacity(selected ? 1 : 0.6))
                .frame(width: Self.height - 16, height: Self.height - 16)
                .contentShape(.circle)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Search")
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
