import SwiftUI

/// The phia bar. A glass capsule of tabs, and a glass back circle that enters beside it when the
/// selected tab has something pushed. Both live in one container so the glass splits and rejoins.
/// The only input is `router.isOnRoot`; pushed screens never talk to this view.
struct TabBar: View {
    @Environment(Router.self) private var router
    @Namespace private var glass
    @Namespace private var pill

    static let height: CGFloat = 58
    static let bottomPadding: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            GlassEffectContainer(spacing: 16) {
                HStack(spacing: 16) {
                    if !router.isOnRoot {
                        backButton
                            .glassEffectID("back", in: glass)
                    }
                    capsule
                        .glassEffectID("tabs", in: glass)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, Self.bottomPadding)
        .ignoresSafeArea(edges: .bottom)
        .animation(.easeInOut, value: router.isOnRoot)
    }

    private var backButton: some View {
        Button {
            HapticManager.medium()
            router.back()
        } label: {
            Icon(.caretLeft, size: 22)
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
        }
        .buttonStyle(.plain)
        .glassEffect(.clear.interactive(), in: .circle)
        .accessibilityLabel("Back")
    }

    private var capsule: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let selected = router.selectedTab == tab
                Button {
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
        }
        .animation(.snappy, value: router.selectedTab)
        .glassEffect(.clear.interactive(), in: .capsule)
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
