import SwiftUI

/// What a screen says when it has nothing to show: one line in the display face and a quiet
/// second line, in glass, centred in the space. The map's "Nowhere yet", made the one empty state
/// for every screen, so a list and a map go quiet in the same voice.
struct EmptyNote: View {
    let title: String
    var detail: String?
    /// Something is still happening: a spinner sits before the title.
    var busy = false

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 10) {
                if busy {
                    ProgressView()
                }
                Text(title)
                    .font(.display(24))
            }
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .glassEffect(.clear, in: .rect(cornerRadius: 24))
        .allowsHitTesting(false)
    }
}
