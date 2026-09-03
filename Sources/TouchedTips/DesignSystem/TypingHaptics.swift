import CoreHaptics

/// Every tap for a run of typing, handed to CoreHaptics as one pattern before the first glyph, so
/// the gaps between taps are exact rather than whatever the main thread was doing. Falls back to
/// nothing on hardware without haptics.
@MainActor
final class TypingHaptics {
    struct Tap {
        let at: TimeInterval
        let intensity: Float
        let sharpness: Float

        /// A letter landing: quick and crisp.
        static func tick(at time: TimeInterval) -> Tap {
            Tap(at: time, intensity: 0.45, sharpness: 0.7)
        }

        /// A question mark striking, before it lands.
        static func strike(at time: TimeInterval) -> Tap {
            Tap(at: time, intensity: 0.6, sharpness: 0.5)
        }

        /// A question mark landing: full weight, soft edge.
        static func thud(at time: TimeInterval) -> Tap {
            Tap(at: time, intensity: 1, sharpness: 0.25)
        }
    }

    private let engine: CHHapticEngine?

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            engine = nil
            return
        }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
    }

    /// Spins the engine up so `play` starts on the first tap and not a few milliseconds after.
    func prepare() {
        try? engine?.start()
    }

    /// Starts the pattern now; `at` on each tap is measured from this call.
    func play(_ taps: [Tap]) {
        guard let engine, !taps.isEmpty else { return }
        let events = taps.map { tap in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: tap.intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: tap.sharpness),
                ],
                relativeTime: tap.at
            )
        }
        do {
            try engine.start()
            let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            Log.ui.error("typing haptics: \(error.localizedDescription)")
        }
    }
}
