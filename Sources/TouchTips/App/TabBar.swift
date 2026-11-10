import SwiftUI

/// The bar: a capsule holding the two tabs, a glass circle for search on the right, and a back
/// circle on the left while something is pushed. All three share one glass container, so the back
/// button grows out of the capsule and melts back into it. The pill in the capsule follows a finger:
/// touch, slide, let go, and it settles on the nearest tab.
struct TabBar: View {
    @Environment(Router.self) private var router
    @Namespace private var glass

    static let height: CGFloat = 58
    static let bottomPadding: CGFloat = 24
    /// How far above the bottom safe area content stops, so nothing ends under the capsule.
    fileprivate static let contentInset = height + bottomPadding + 8 - 34

    private static let tabs: [AppTab] = [.people, .map]

    /// Where the pill is under a finger, as a tab index with a fraction. Nil when nobody is dragging.
    @State private var dragIndex: CGFloat?
    /// The tab the pill would land on now. Ticks when it changes under the finger.
    @State private var landing: Int?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    if !router.isOnRoot {
                        sideButton(.caretLeft, label: "Back") {
                            HapticManager.medium()
                            router.back()
                        }
                        .glassEffectID("back", in: glass)
                    }
                    capsule
                        .glassEffectID("tabs", in: glass)
                    sideButton(.magnifyingGlass, label: "Search", selected: router.selectedTab == .search) {
                        HapticManager.selection()
                        router.search()
                    }
                    .glassEffectID("search", in: glass)
                }
            }
            // Instagram's bar: scrolling down shrinks the three shapes together from their feet,
            // and the first touch on the small bar brings it back before the tap lands.
            .scaleEffect(1 - router.barProgress * 0.15, anchor: .bottom)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0).onChanged { _ in router.restoreBar() }
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, Self.bottomPadding)
        .ignoresSafeArea(edges: .bottom)
        .animation(.appleMusic, value: router.isOnRoot)
    }

    /// Back and search share one shape: a capsule the height of the bar, in the same clear glass as
    /// the tabs, so the three shapes read as one bar. The content shape makes the whole circle the target.
    private func sideButton(
        _ glyph: ImageResource, label: String, selected: Bool = false, action: @escaping () -> Void
    ) -> some View {
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

    // MARK: - Capsule

    private var capsule: some View {
        GeometryReader { geometry in
            let width = geometry.size.width / CGFloat(Self.tabs.count)
            ZStack(alignment: .leading) {
                if let pillIndex {
                    Capsule()
                        .fill(Color.pill)
                        .frame(width: width, height: Self.height)
                        .padding(5)
                        .offset(x: pillIndex * width)
                        .scaleEffect(dragIndex == nil ? 1 : 1.06)
                        .padding(-5)
                }
                HStack(spacing: 0) {
                    ForEach(Self.tabs) { tab in
                        glyph(tab, width: width)
                    }
                }
            }
            .contentShape(.capsule)
            .gesture(drag(width: width))
            // Selection made elsewhere, a tab tapped from a notification say, slides the pill over.
            .animation(.appleInteractive, value: router.selectedTab)
            .animation(.appleInteractive, value: dragIndex == nil)
        }
        .frame(height: Self.height)
        .glassEffect(.clear.interactive(), in: .capsule)
    }

    /// The finger's position while dragging, the selected tab otherwise, nothing on the search tab.
    private var pillIndex: CGFloat? {
        if let dragIndex {
            return dragIndex
        }
        guard let index = Self.tabs.firstIndex(of: router.selectedTab) else { return nil }
        return CGFloat(index)
    }

    private func glyph(_ tab: AppTab, width: CGFloat) -> some View {
        let index = Self.tabs.firstIndex(of: tab) ?? 0
        let selected = landing.map { $0 == index } ?? (router.selectedTab == tab)
        return Image(tab.glyph)
            .renderingMode(.template)
            .foregroundStyle(.white.opacity(selected ? 1 : 0.5))
            .frame(width: width, height: Self.height)
            .animation(.appleInteractive, value: selected)
            .accessibilityElement()
            .accessibilityLabel(tab.label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityAction { select(tab, tapped: true) }
    }

    /// Touch down and the pill slides under the finger; from then on it is the finger, held inside
    /// the capsule. Crossing from one tab's half to the other's ticks. Letting go lands it.
    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let finger = value.location.x / width - 0.5
                let index = min(CGFloat(Self.tabs.count - 1), max(0, finger))
                let nearest = Int(index.rounded())
                if dragIndex == nil {
                    withAnimation(.appleInteractive) { dragIndex = index }
                    landing = nearest
                } else {
                    dragIndex = index
                    if nearest != landing {
                        landing = nearest
                        HapticManager.selection()
                    }
                }
            }
            .onEnded { value in
                let tab = Self.tabs[landing ?? 0]
                withAnimation(.appleInteractive) {
                    dragIndex = nil
                    landing = nil
                }
                select(tab, tapped: abs(value.translation.width) < 8)
            }
    }

    /// A tap on the tab you are on pops to its root or scrolls to the top. A slide that lands on it
    /// only stays there.
    private func select(_ tab: AppTab, tapped: Bool) {
        if router.selectedTab == tab {
            if tapped {
                HapticManager.selection()
                router.reselect()
            }
        } else {
            HapticManager.selection()
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
