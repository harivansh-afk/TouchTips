import SwiftUI
import TouchTipsCore

/// A meeting is either confirmed by the user or still a suggestion. No meeting, no dot.
struct ConfidenceDot: View {
    let meet: Meet?

    var body: some View {
        if let meet {
            Circle()
                .fill(.white.opacity(meet.isConfirmed ? 1 : 0))
                .overlay { Circle().strokeBorder(.white, lineWidth: 1.5) }
                .frame(width: 9, height: 9)
                .accessibilityLabel(meet.isConfirmed ? "Confirmed meeting" : "Suggested meeting")
        }
    }
}
