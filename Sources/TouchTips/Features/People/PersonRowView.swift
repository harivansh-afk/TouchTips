import SwiftUI
import TouchTipsCore

struct PersonRowView: View {
    let row: PersonRow
    /// Off when the place is the heading above: the second line is the date instead, and the
    /// short date on the right goes with it.
    var showsPlace = true

    /// Avatar width plus the gap to the text.
    nonisolated static let textLeading: CGFloat = 44 + 12

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatar(contactID: row.id, initials: row.person.initials, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.person.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                let subtitle = showsPlace ? Format.rowSubtitle(row) : row.meet.map(Format.dateLine) ?? ""
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if showsPlace, let meet = row.meet {
                    Text(Format.rowDate(meet))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ConfidenceDot(meet: row.meet)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

#Preview {
    let now = Date()
    let place = Place(
        id: 1,
        key: "c:37.776,-122.423",
        latitude: 37.776,
        longitude: -122.423,
        name: "Blue Bottle, Hayes Valley"
    )
    let meet = Meet(
        contactID: "dp", start: now.addingTimeInterval(-3600), end: now, precision: .day, placeID: 1, tier: .witnessed,
        userSet: false, addSeenStart: nil, addSeenEnd: nil, computedAt: now
    )
    List {
        PersonRowView(row: PersonRow(
            person: Person(contactID: "dp", name: "Dev Patel", beforeInstall: false, createdAt: now),
            meet: meet,
            place: place
        ))
        PersonRowView(
            row: PersonRow(
                person: Person(contactID: "dp", name: "Dev Patel", beforeInstall: false, createdAt: now),
                meet: meet,
                place: place
            ),
            showsPlace: false
        )
        PersonRowView(row: PersonRow(
            person: Person(contactID: "ln", name: "Lena Novak", beforeInstall: true, createdAt: now),
            meet: nil,
            place: nil
        ))
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(Color.ground)
    .preferredColorScheme(.dark)
}

/// A single separator per row, inset to the name. Used by every ordinary contact list.
private struct PersonListRow: ViewModifier {
    let showSeparator: Bool

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 4)
            .overlay(alignment: .bottom) {
                if showSeparator {
                    Rectangle()
                        .fill(Color.hairline)
                        .frame(height: 0.5)
                        .padding(.leading, PersonRowView.textLeading)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

extension View {
    func personListRow(showSeparator: Bool) -> some View {
        modifier(PersonListRow(showSeparator: showSeparator))
    }
}
