import SwiftUI
import TouchTipsCore

/// Empty for no meeting; dim filled for suggested details; bright filled for confirmed details.
struct ConfidenceDot: View {
    let meet: Meet?

    private var fillOpacity: Double {
        guard let meet else { return 0 }
        return meet.isConfirmed ? 1 : 0.4
    }

    private var accessibilityDescription: String {
        guard let meet else { return "No meeting recorded" }
        return meet.isConfirmed ? "Confirmed meeting" : "Suggested meeting"
    }

    var body: some View {
        Circle()
            .fill(.white.opacity(fillOpacity))
            .overlay {
                Circle().strokeBorder(.white.opacity(meet == nil ? 1 : fillOpacity), lineWidth: 1.5)
            }
            .frame(width: 9, height: 9)
            .accessibilityLabel(accessibilityDescription)
    }
}
