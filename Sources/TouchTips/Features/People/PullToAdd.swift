import SwiftUI

extension View {
    /// Pull the list down past its top and a plus appears in the space, its ring closing as the pull
    /// grows. Let go with the ring closed and `action` runs. Let go early and nothing happens. The
    /// one way to add from the People tab; VoiceOver gets the same action by name.
    func pullsDownToAdd(_ action: @escaping () -> Void) -> some View {
        modifier(PullsDownToAdd(action: action))
    }
}

private struct PullsDownToAdd: ViewModifier {
    let action: () -> Void

    /// Points of pull that close the ring.
    static let distance: CGFloat = 96

    /// How far the list is pulled past its top. Zero whenever it is not.
    @State private var pull: CGFloat = 0
    @State private var isDragging = false
    /// The ring closed under the finger. Cleared the moment the finger lifts or the pull eases back.
    @State private var armed = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                -(geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, pulled in
                pull = max(0, pulled)
                guard isDragging else { return }
                let closed = pull >= Self.distance
                if closed != armed {
                    armed = closed
                    // The ring meets itself: one tick, so the finger knows it can let go.
                    if closed {
                        HapticManager.medium()
                    }
                }
            }
            .onScrollPhaseChange { _, phase in
                let wasDragging = isDragging
                isDragging = phase == .interacting
                if wasDragging, !isDragging, armed {
                    action()
                }
                if !isDragging {
                    armed = false
                }
            }
            .overlay(alignment: .top) {
                PullIndicator(progress: min(1, pull / Self.distance), armed: armed)
                    // Centred in the pulled space, so it rides down with the list and leaves with it.
                    .frame(height: pull)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .accessibilityAction(named: "Add", action)
    }
}

/// The plus in its glass circle. The ring is drawn from the top, clockwise, as far as the pull has
/// come; the glyph brightens with it. Closed, the whole thing sits up a touch to say "now".
private struct PullIndicator: View {
    let progress: CGFloat
    let armed: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.pill, lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(0.75)
            Icon(.plus, size: 20)
                .foregroundStyle(.white.opacity(0.4 + 0.6 * progress))
        }
        .frame(width: 44, height: 44)
        .glassEffect(.clear, in: .circle)
        .scaleEffect((0.6 + 0.4 * progress) * (armed ? 1.1 : 1))
        .opacity(min(1, progress * 3))
        .animation(.appleInteractive, value: armed)
    }
}
