import SwiftUI

public extension AnyTransition {
    /// A transition that replaces the view with a blur and fade effect.
    static var blurReplace: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurTransitionModifier(blur: 8, opacity: 0),
                identity: BlurTransitionModifier(blur: 0, opacity: 1)
            ),
            removal: .modifier(
                active: BlurTransitionModifier(blur: 8, opacity: 0),
                identity: BlurTransitionModifier(blur: 0, opacity: 1)
            )
        )
    }
}

private struct BlurTransitionModifier: ViewModifier {
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .opacity(opacity)
    }
}
