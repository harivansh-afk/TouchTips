import SwiftUI
import TouchTipsCore

/// Fill encodes the tier. A dashed ring means we have no date at all.
struct ConfidenceDot: View {
    let tier: Tier?

    var body: some View {
        Circle()
            .fill(.white.opacity(fill))
            .overlay {
                Circle().strokeBorder(.white, style: StrokeStyle(lineWidth: 1.5, dash: tier == nil ? [2, 2] : []))
            }
            .frame(width: 9, height: 9)
            .opacity(tier == nil ? 0.55 : 1)
            .accessibilityLabel(Format.tierName(tier))
    }

    private var fill: Double {
        switch tier {
        case .exact: 1
        case .witnessed: 0.72
        case .inferred: 0.4
        case .dateOnly, nil: 0
        }
    }
}
