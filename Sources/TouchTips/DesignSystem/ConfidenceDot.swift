import SwiftUI
import TouchTipsCore

/// Filled for a confirmed meeting; an empty ring for a suggestion or an undocumented contact.
struct ConfidenceDot: View {
    let meet: Meet?

    var body: some View {
        Circle()
            .fill(.white.opacity(meet?.isConfirmed == true ? 1 : 0))
            .overlay { Circle().strokeBorder(.white, lineWidth: 1.5) }
            .frame(width: 9, height: 9)
            .accessibilityLabel(meet == nil ? "No meeting recorded" : meet?
                .isConfirmed == true ? "Confirmed meeting" : "Suggested meeting")
    }
}
