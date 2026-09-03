import SwiftUI
import TouchedTipsCore

struct PersonRowView: View {
    let row: PersonRow

    /// Avatar width plus the gap to the text.
    static let textLeading: CGFloat = 42 + 14

    var body: some View {
        HStack(spacing: 14) {
            ContactAvatar(contactID: row.id, initials: row.person.initials)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.person.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                let subtitle = Format.rowSubtitle(row)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        // The hairline starts where the text does, after the avatar, and ends at the row inset,
        // which is what mixbridge's rows do. The button wrapper would otherwise start it under
        // the avatar.
        .alignmentGuide(.listRowSeparatorLeading) { _ in Self.textLeading }
    }
}

#Preview {
    let now = Date()
    let place = Place(id: 1, key: "c:37.776,-122.423", latitude: 37.776, longitude: -122.423, name: "Blue Bottle, Hayes Valley")
    let meet = Meet(
        contactID: "dp", start: now.addingTimeInterval(-3600), end: now, precision: .day, placeID: 1, tier: .witnessed,
        userSet: false, addSeenStart: nil, addSeenEnd: nil, computedAt: now
    )
    List {
        PersonRowView(row: PersonRow(person: Person(contactID: "dp", name: "Dev Patel", beforeInstall: false, createdAt: now), meet: meet, place: place))
        PersonRowView(row: PersonRow(person: Person(contactID: "ln", name: "Lena Novak", beforeInstall: true, createdAt: now), meet: nil, place: nil))
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(Color.ground)
    .preferredColorScheme(.dark)
}
