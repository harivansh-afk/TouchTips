import SwiftUI

/// The small uppercase caption over a block: "First met", "Where". One style, used everywhere.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .kerning(1)
            .foregroundStyle(.secondary)
    }
}
