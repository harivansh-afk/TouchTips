import SwiftUI
import TouchTipsCore

/// Everyone on one line. The line runs down the left; each person is their confidence dot on it,
/// a month is a tick, and a stretch with nobody in it says how long it was. Newest at the top.
struct PeopleTimeline: View {
    let items: [TimelineItem]
    var undocumented: [PersonRow] = []

    @Environment(Router.self) private var router
    @Environment(\.zoomNamespace) private var zoom

    /// The spine uses the existing list margin without adding to the content inset.
    private static let spineX: CGFloat = 8

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
                .id(item.id)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(marker(for: item))
            }
            if !undocumented.isEmpty {
                undocumentedRow
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .environment(\.defaultMinListRowHeight, 0)
        .listRowSpacing(0)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.ground)
    }

    /// The marker uses the full cell width so its leading offset stays in the list margin.
    private func marker(for item: TimelineItem) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.hairline)
                .frame(width: 1)
                .padding(.leading, Self.spineX - 0.5)
                .padding(.top, item.id == items.first?.id ? 22 : 0)
                .padding(.bottom, item.id == items.last?.id ? 22 : 0)
            switch item {
            case let .person(row):
                ConfidenceDot(meet: row.meet)
                    .background { Circle().fill(Color.ground).padding(-3) }
                    .padding(.leading, Self.spineX - 4.5)
            case .month:
                Rectangle()
                    .fill(.white)
                    .frame(width: 1, height: 14)
                    .padding(.leading, Self.spineX - 0.5)
                    .offset(y: 8)
            case .quiet:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func tick(_ title: String) -> some View {
        Text(title)
            .font(.display(26))
            .padding(.top, 22)
            .padding(.bottom, 6)
    }

    private func quiet(_ days: Int) -> some View {
        Text(Format.quiet(days: days))
            .font(.display(18))
            .foregroundStyle(.tertiary)
            .padding(.vertical, 8)
    }

    private func person(_ row: PersonRow) -> some View {
        Button {
            HapticManager.selection()
            router.open(person: row.id)
        } label: {
            HStack(spacing: 12) {
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
