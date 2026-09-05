import SwiftUI
import TouchTipsCore

extension EnvironmentValues {
    @Entry var zoomNamespace: Namespace.ID?
}

/// The bare list of people in sections. Shared by the People tab, in both of its grouped layouts,
/// and the search tab.
struct PeopleList: View {
    let sections: [PeopleSection]
    var undocumented: [PersonRow] = []
    /// Off when the sections are places: the heading says where, so the rows say when instead.
    var showsPlace = true
    /// Search shows matching undocumented people inline; the home tab folds them into one row.
    var expandUndocumented = false
    /// The active search text, only used to pick the empty state.
    var query = ""

    @Environment(Router.self) private var router
    @Environment(\.zoomNamespace) private var zoom

    private var isEmpty: Bool {
        sections.isEmpty && undocumented.isEmpty
    }

    var body: some View {
        List {
            if isEmpty, !query.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            } else {
                ForEach(sections) { section in
                    heading(section.title, subtitle: section.subtitle, placeID: section.placeID)
                        .id(section.id)
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
        .environment(\.defaultMinListRowHeight, 0)
        .listRowSpacing(0)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.ground)
    }

    /// The heading is a row, not a section header, so it scrolls with the list instead of pinning.
    /// A place's heading opens it on the map, the way the person screen's place line does.
    private func heading(_ title: String, subtitle: String? = nil, placeID: Int64? = nil) -> some View {
        Group {
            if let placeID {
                Button {
                    HapticManager.selection()
                    router.showPlace(placeID)
                } label: {
                    headingLabel(title, subtitle: subtitle)
                }
                .buttonStyle(.press)
                .accessibilityHint("Shows this place on the map")
            } else {
                headingLabel(title, subtitle: subtitle)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
    }

    private func headingLabel(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.display(26))
                .foregroundColor(Color.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
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
                PersonRowView(row: row, showsPlace: showsPlace)
            }
            .buttonStyle(.press)
            .personListRow(showSeparator: index < rows.count - 1)
            .personTransitionSource(id: row.id, in: zoom)
            .personSwipeActions(row: row)
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
            }
            Spacer(minLength: 8)
            ConfidenceDot(meet: nil)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}
