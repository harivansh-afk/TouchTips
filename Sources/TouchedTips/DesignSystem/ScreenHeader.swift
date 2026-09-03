import SwiftUI

/// The header a root screen draws itself, in place of a navigation bar. The bar is hidden on roots
/// so a push animates nothing but the zoom; this is what the bar used to show.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var hidden = false
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.display(36))
                .fixedSize()
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .opacity(hidden ? 0 : 1)
        .allowsHitTesting(!hidden)
        .animation(.easeOut(duration: 0.15), value: hidden)
    }
}

/// Bar buttons as iOS 26 draws separated toolbar items: each its own 44-point clear-glass circle,
/// eight points apart, the same gap a fixed toolbar spacer leaves.
struct HeaderButtons<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                content()
            }
        }
    }
}

/// One glyph in its own circle, sized like a navigation bar item.
struct HeaderButton: View {
    let glyph: ImageResource
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.light()
            action()
        } label: {
            Icon(glyph, size: 22)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.clear.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}

/// Fades a root's header once the list has scrolled under it. Same threshold everywhere.
extension View {
    func hidesHeaderOnScroll(_ hidden: Binding<Bool>) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            let shouldHide = offset > 24
            if shouldHide != hidden.wrappedValue { hidden.wrappedValue = shouldHide }
        }
    }
}
