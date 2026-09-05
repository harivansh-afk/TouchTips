import SwiftUI

extension View {
    /// Instagram's tab bar on a scrolling screen: dragging down the list shrinks the bar, dragging
    /// back up grows it, and the bar tracks the finger in between. The progress lives on the
    /// router, so the bar in the shell can read it from any tab.
    func minimizesTabBarOnScroll() -> some View {
        modifier(MinimizesTabBarOnScroll())
    }
}

private struct MinimizesTabBarOnScroll: ViewModifier {
    @Environment(Router.self) private var router

    /// Points of drag that take the bar from full size to minimised.
    private static let distance: CGFloat = 100
    /// Movement smaller than this is noise: rows resizing under the scroll, or the finger settling
    /// as it lifts. It neither changes the direction nor moves the anchor.
    private static let deadband: CGFloat = 2

    @State private var isDragging = false
    /// Short content never minimises the bar; there is nothing to make room for.
    @State private var isLargerContent = false
    @State private var scrollOffset: CGFloat = 0
    /// The offset the current run of progress is measured from. Set when the finger lands and on
    /// every change of direction, so reversing eats back from wherever the bar is, not from zero.
    @State private var shiftOffset: CGFloat = 0
    /// The last direction the finger moved by more than the deadband. Nil until it has.
    @State private var isScrollingDown: Bool?

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height > geometry.containerSize.height
            } action: { _, larger in
                isLargerContent = larger
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                Self.offset(of: geometry)
            } action: { old, new in
                guard isDragging else { return }
                scrollOffset = new
                let delta = new - old
                if abs(delta) >= Self.deadband, isScrollingDown != (delta > 0) {
                    isScrollingDown = delta > 0
                    shiftOffset = new - router.barProgress * Self.distance
                }
                // Unanimated: the bar follows the finger.
                router.barProgress = progress(at: new)
            }
            .onScrollPhaseChange { old, new, context in
                isDragging = new == .interacting
                let offset = Self.offset(of: context.geometry)
                if new == .interacting {
                    // The finger landed, maybe far from where the last drag ended. Anchor here.
                    scrollOffset = offset
                    isScrollingDown = nil
                    shiftOffset = offset - router.barProgress * Self.distance
                } else if old == .interacting {
                    scrollOffset = offset
                    snap()
                }
            }
    }

    private static func offset(of geometry: ScrollGeometry) -> CGFloat {
        geometry.contentOffset.y + geometry.contentInsets.top
    }

    private func progress(at offset: CGFloat) -> CGFloat {
        min(1, max(0, (offset - shiftOffset) / Self.distance))
    }

    /// The finger lifted: a drag that was going down ends minimised, one going up ends full size,
    /// whatever the speed. Inside the first half-distance of the top the bar always comes back, so
    /// the list never opens under a small bar.
    private func snap() {
        let minimised: Bool
        if scrollOffset <= Self.distance / 2 || !isLargerContent {
            minimised = false
        } else if let isScrollingDown {
            minimised = isScrollingDown
        } else {
            minimised = router.barProgress > 0.5
        }
        let target: CGFloat = minimised ? 1 : 0
        withAnimation(.appleMusic) { router.barProgress = target }
        isScrollingDown = nil
        shiftOffset = scrollOffset - target * Self.distance
    }
}
