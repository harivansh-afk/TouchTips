import SwiftUI
import TouchTipsCore

/// The bare list of people grouped by month. Shared by the People tab and the search tab.
struct PeopleList: View {
    let sections: [PeopleSection]
    /// The active search text, only used to pick the empty state.
    var query = ""

    @Namespace private var zoom

    var body: some View {
        List {
            if sections.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            } else {
                ForEach(sections) { section in
                    // The heading is a row, not a section header, so it scrolls with the list instead of pinning.
                    Section {
                        Text(section.title)
                            .font(.display(26))
                            .foregroundColor(Color.primary)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)

                    let rows = section.rows.indexedRows()
                    ForEach(rows) { indexed in
                        let row = indexed.item
                        let index = indexed.index
                        NavigationLink(value: Destination.person(row.id)) {
                            PersonRowView(row: row)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparatorTint(.white.opacity(0.12))
                        .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
                        .listRowSeparator(index == rows.count - 1 ? .hidden : .visible, edges: .bottom)
                        .matchedTransitionSource(id: row.id, in: zoom)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationDestination(for: Destination.self) { destination in
            DestinationView(destination: destination, zoom: zoom)
        }
    }
}
