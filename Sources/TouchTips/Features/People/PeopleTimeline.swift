import SwiftUI
import TouchTipsCore

/// Everyone on one line. The line runs down the left; each person is their confidence dot on it,
/// a month is a tick, and a stretch with nobody in it says how long it was. Newest at the top.
struct PeopleTimeline: View {
    let items: [TimelineItem]
    var undocumented: [PersonRow] = []

    @Environment(Router.self) private var router
    @Environment(\.zoomNamespace) private var zoom

    /// The column the line runs through, before the avatar.
    private static let gutter: CGFloat = 24

    var body: some View {
        List {
            ForEach(items) { item in
                Group {
                    switch item {
                    case let .month(_, title): tick(title)
                    case let .quiet(_, days): quiet(days)
                    case let .person(row): person(row)
                    }
                }
                .background(alignment: .leading) {
                    Rectangle()
                        .fill(Color.hairline)
                        .frame(width: 1)
                        .padding(.leading, Self.gutter / 2 - 0.5)
                        .padding(.top, item.id == items.first?.id ? 22 : 0)
                        .padding(.bottom, item.id == items.last?.id ? 22 : 0)
                }
                .id(item.id)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            if !undocumented.isEmpty {
                undocumentedRow
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .environment(\.defaultMinListRowHeight, 0)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.ground)
    }

    /// A month: the line brightens for a moment, and the name sits where the rows start.
    private func tick(_ title: String) -> some View {
        HStack(spacing: 14) {
            Rectangle()
                .fill(.white)
                .frame(width: 1, height: 14)
                .frame(width: Self.gutter)
            Text(title)
                .font(.display(26))
        }
        .padding(.top, 22)
        .padding(.bottom, 6)
    }

    /// Nobody for a while. Said in the serif, quietly, so the space reads as time and not as a bug.
    private func quiet(_ days: Int) -> some View {
        HStack(spacing: 14) {
            Color.clear.frame(width: Self.gutter, height: 1)
            Text(Format.quiet(days: days))
                .font(.display(18))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }

    private func person(_ row: PersonRow) -> some View {
        Button {
            HapticManager.selection()
            router.open(person: row.id)
        } label: {
            HStack(spacing: 12) {
                ConfidenceDot(meet: row.meet)
                    // A ring of ground behind the dot, so the line stops at a hollow dot instead of running through it.
                    .background { Circle().fill(Color.ground).padding(-3) }
                    .frame(width: Self.gutter)
                ContactAvatar(contactID: row.id, initials: row.person.initials, size: 44)
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
                if let meet = row.meet {
                    Text(Format.rowDate(meet))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.press)
        .personTransitionSource(id: row.id, in: zoom)
        .personSwipeActions(row: row)
    }

    /// After the line ends: the same one row the list shows for everyone without a date.
    private var undocumentedRow: some View {
        Button {
            HapticManager.selection()
            router.navigate(to: .undocumented)
        } label: {
            UndocumentedRowLabel(count: undocumented.count)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(.rect)
        }
        .buttonStyle(.press)
        .padding(.top, 20)
    }
}
