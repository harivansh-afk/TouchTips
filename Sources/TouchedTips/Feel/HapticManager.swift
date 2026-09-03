//
//  HapticManager.swift
//
//  Began as mixbridge's file. Reshaped after phia's: main-actor only, no thread checks,
//  one prepared generator per style, and a hardware check so simulators and iPads stay quiet.
//

import CoreHaptics
import SwiftUI
import UIKit

/// Centralized haptic feedback. Every call site is a SwiftUI action or a main-actor model, so the
/// type is main-actor isolated and the generators are created once.
@MainActor
enum HapticManager {
    private static let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    /// Light impact - for subtle interactions
    static func light() { impact(lightGenerator) }

    /// Medium impact - for standard button taps and selections
    static func medium() { impact(mediumGenerator) }

    /// Heavy impact - for significant actions
    static func heavy() { impact(heavyGenerator) }

    /// Selection feedback - for navigation and tab changes
    static func selection() {
        guard supported else { return }
        selectionGenerator.prepare()
        selectionGenerator.selectionChanged()
    }

    /// Success notification - for successful operations
    static func success() { notify(.success) }

    /// Warning notification - for destructive actions
    static func warning() { notify(.warning) }

    /// Error notification - for failed operations
    static func error() { notify(.error) }

    private static func impact(_ generator: UIImpactFeedbackGenerator) {
        guard supported else { return }
        generator.prepare()
        generator.impactOccurred()
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard supported else { return }
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(type)
    }
}

/// ViewModifier to add haptic feedback to any view interaction
struct HapticFeedback: ViewModifier {
    let style: HapticStyle

    enum HapticStyle {
        case light, medium, heavy, selection, success, warning, error
    }

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                TapGesture().onEnded {
                    switch style {
                    case .light: HapticManager.light()
                    case .medium: HapticManager.medium()
                    case .heavy: HapticManager.heavy()
                    case .selection: HapticManager.selection()
                    case .success: HapticManager.success()
                    case .warning: HapticManager.warning()
                    case .error: HapticManager.error()
                    }
                }
            )
    }
}

extension View {
    /// Add haptic feedback to any tappable view
    func haptic(_ style: HapticFeedback.HapticStyle = .light) -> some View {
        modifier(HapticFeedback(style: style))
    }
}
