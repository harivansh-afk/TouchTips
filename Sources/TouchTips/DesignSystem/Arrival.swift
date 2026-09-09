import SwiftUI

/// How the finished app comes into view once the first-run screen has left. `.hidden` while that
/// screen is still over it, `.arriving` while its parts rise into place one beat apart, and
/// `.settled` ever after, including every warm launch, when nothing moves at all.
enum ArrivalPhase {
    case hidden, arriving, settled
}

extension EnvironmentValues {
    @Entry var arrival: ArrivalPhase = .settled
}

extension View {
    /// Rises into place `order` beats after the first part of the screen, once the app is arriving.
    /// Hidden until then; untouched once the app has settled, so a warm launch pays nothing.
    func arrives(order: Int) -> some View {
        modifier(Arrives(order: order))
    }
}

private struct Arrives: ViewModifier {
    @Environment(\.arrival) private var arrival
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let order: Int

    /// The gap between one part landing and the next starting.
    static let beat: TimeInterval = 0.045
    /// Rows past this one land together: a long list would otherwise take seconds to finish.
    private static let lastBeat = 10
    /// How far below its place a part starts.
    private static let rise: CGFloat = 16

    func body(content: Content) -> some View {
        let visible = arrival != .hidden
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : Self.rise)
            .animation(animation, value: visible)
    }

    private var animation: Animation? {
        guard arrival == .arriving else { return nil }
        return .spring(response: 0.5, dampingFraction: 1)
            .delay(Double(min(order, Self.lastBeat)) * Self.beat)
    }
}
