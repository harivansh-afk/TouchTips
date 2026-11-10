import SwiftUI
import TouchTipsCore

extension EnvironmentValues {
    @Entry var zoomNamespace: Namespace.ID?
}

/// The bare list of people in sections. Shared by the People tab's month layout and the search tab.
struct PeopleList: View {
    let sections: [PeopleSection]
    var undocumented: [PersonRow] = []
    /// Search shows matching undocumented people inline; the home tab folds them into one row.
    var expandUndocumented = false
    /// The active search text, only used to pick the empty state.
    var query = ""

    @Environment(Router.self) private var router
    @Environment(\.zoomNamespace) private var zoom

    private var isEmpty: Bool {
        sections.isEmpty && undocumented.isEmpty
    }

    private static let undocumentedKey = "undocumented"

    /// The beat each heading lands on when the app arrives; its rows follow one beat apart. The
    /// header is beat zero. Far down the list the beats are capped, so this only matters up top.
    private var arrivalOrders: [String: Int] {
        var orders: [String: Int] = [:]
        var next = 1
        for section in sections {
            orders[section.id] = next
            next += 1 + section.rows.count
        }
        orders[Self.undocumentedKey] = next
        return orders
    }

    var body: some View {
        List {
            if isEmpty, !query.isEmpty {
                EmptyNote(title: "No Results", detail: "Nothing matches “\(query)”.")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } else {
                let starts = arrivalOrders
                ForEach(sections) { section in
                    heading(section.title)
                        .id(section.id)
                        .arrives(order: starts[section.id, default: 1])
                    rows(section.rows, from: starts[section.id, default: 1] + 1)
                }
                if !undocumented.isEmpty {
                    if expandUndocumented {
                        heading("Undocumented")
                            .arrives(order: starts[Self.undocumentedKey, default: 1])
                        rows(undocumented, from: starts[Self.undocumentedKey, default: 1] + 1)
                    } else {
                        undocumentedRow
                            .arrives(order: starts[Self.undocumentedKey, default: 1])
                    }
                }
            }
        }
        .environment(\.defaultMinListRowHeight, 0)
        .listRowSpacing(0)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.ground)
    }

    /// The heading is a row, not a section header, so it scrolls with the list instead of pinning.
    private func heading(_ title: String) -> some View {
        Text(title)
            .font(.display(26))
            .foregroundColor(Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            .listRowSeparator(.hidden)
    }

    private func rows(_ people: [PersonRow], from firstOrder: Int) -> some View {
        let rows = people.indexedRows()
        return ForEach(rows) { indexed in
            let row = indexed.item
            let index = indexed.index
            Button {
                HapticManager.selection()
                router.open(person: row.id)
            } label: {
                PersonRowView(row: row)
            }
            .buttonStyle(.press)
            .personListRow(showSeparator: index < rows.count - 1)
            .personTransitionSource(id: row.id, in: zoom)
            .personSwipeActions(row: row)
            .arrives(order: firstOrder + index)
        }
    }

    /// One row for everyone saved before the app existed. The home tab stays about people it knows something about.
    private var undocumentedRow: some View {
        NavigationLink(value: Destination.undocumented) {
            UndocumentedRowLabel(count: undocumented.count)
        }
        .padding(.top, 20)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

/// The count of people with no date yet, and why. Drawn at the end of every home layout.
struct UndocumentedRowLabel: View {
    let count: Int

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) undocumented")
                    .font(.body.weight(.medium))
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 8)
            ConfidenceDot(meet: nil)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}
