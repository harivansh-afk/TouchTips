import SwiftUI
import TouchTipsCore

struct PersonRowView: View {
    let row: PersonRow

    var body: some View {
        HStack(spacing: 14) {
            InitialsAvatar(initials: row.person.initials)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.person.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(Format.rowSubtitle(row))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if let meet = row.meet {
                    Text(Format.rowDate(meet))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ConfidenceDot(tier: row.meet?.tier)
            }
        }
        .padding(.vertical, 4)
    }
}
