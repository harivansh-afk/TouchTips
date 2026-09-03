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
        .padding(.top, 4)
        .padding(.bottom, 8)
        .opacity(hidden ? 0 : 1)
        .allowsHitTesting(!hidden)
        .animation(.easeOut(duration: 0.15), value: hidden)
    }
}

/// A glyph in a system glass circle, the size the navigation bar would have used.
struct HeaderButton: View {
    let glyph: ImageResource
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.light()
            action()
        } label: {
            Icon(glyph)
                .frame(width: 26, height: 26)
                .contentShape(.circle)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
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
