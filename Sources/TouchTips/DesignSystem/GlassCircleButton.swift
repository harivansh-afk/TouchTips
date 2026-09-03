import SwiftUI

/// A Phosphor glyph in its own clear-glass circle. Draws its own background so it can fade
/// out as a whole, the way mixbridge's avatar button does in the Library bar.
struct GlassCircleButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(icon)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .glassEffect(.clear.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}
