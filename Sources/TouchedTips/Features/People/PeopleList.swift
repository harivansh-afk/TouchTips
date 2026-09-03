import SwiftUI
import TouchedTipsCore

/// The namespace rows register their zoom source in, so a list pushed from this one can zoom too.
private struct ZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }
}

/// The bare list of people grouped by month. Shared by the People tab and the search tab.
struct PeopleList: View {
    let sections: [PeopleSection]
    var undocumented: [PersonRow] = []
    /// Search shows matching undocumented people inline; the home tab folds them into one row.
    var expandUndocumented = false
    /// The active search text, only used to pick the empty state.
    var query = ""

    @Environment(Router.self) private var router
    @Namespace private var zoom

    private var isEmpty: Bool { sections.isEmpty && undocumented.isEmpty }

    var body: some View {
        List {
            if isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            } else {
                ForEach(sections) { section in
                    heading(section.title)
                    rows(section.rows)
                }
                if !undocumented.isEmpty {
                    if expandUndocumented {
                        heading("Undocumented")
                        rows(undocumented)
                    } else {
                        undocumentedRow
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.ground)
        .environment(\.zoomNamespace, zoom)
        .navigationDestination(for: Destination.self) { destination in
            DestinationView(destination: destination, zoom: zoom)
        }
    }

    // The heading is a row, not a section header, so it scrolls with the list instead of pinning.
    private func heading(_ title: String) -> some View {
        Section {
            Text(title)
                .font(.display(26))
                .foregroundColor(Color.primary)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
    }

    private func rows(_ people: [PersonRow]) -> some View {
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
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowSeparatorTint(.hairline)
            .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
            .listRowSeparator(index == rows.count - 1 ? .hidden : .visible, edges: .bottom)
            .matchedTransitionSource(id: row.id, in: zoom)
        }
    }

    /// One row for everyone saved before the app existed. The home tab stays about people it knows something about.
    private var undocumentedRow: some View {
        Section {
            NavigationLink(value: Destination.undocumented) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(undocumented.count) undocumented")
                            .font(.body.weight(.medium))
                        Text("Saved before TouchedTips, no date yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    ConfidenceDot(tier: nil)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
                .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] + 16 }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowSeparator(.hidden)
        }
        .listSectionSpacing(20)
    }
}
