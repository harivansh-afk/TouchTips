import SwiftUI

/// A row or inline control under a finger: a little dimmer and a little smaller, on a short spring.
/// No sound of its own; the action it leads to makes the one tick. Glass buttons keep `.glass`.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.appleInteractive, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressStyle {
    static var press: PressStyle { PressStyle() }
}
