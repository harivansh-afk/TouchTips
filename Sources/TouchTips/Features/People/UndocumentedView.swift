import SwiftUI
import TouchTipsCore

/// Everyone saved before touchtips, alphabetical. Tapping one opens the person screen, where a date can be set.
struct UndocumentedView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.zoomNamespace) private var zoom
    @State private var people = PeopleObserver()
    @State private var query = ""
    @State private var visible: [PersonRow] = []

    var body: some View {
        List {
            if visible.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            } else {
                let rows = visible.indexedRows()
                ForEach(rows) { indexed in
                    let row = indexed.item
                    let index = indexed.index
                    NavigationLink(value: Destination.person(row.id)) {
                        PersonRowView(row: row)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparatorTint(.hairline)
                    .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
                    .listRowSeparator(index == rows.count - 1 ? .hidden : .visible, edges: .bottom)
                    .modifier(ZoomSource(id: row.id, namespace: zoom))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.ground)
        .serifTitle("Undocumented")
        .searchable(text: $query, prompt: "Name")
        .onChange(of: query) { _, _ in refilter() }
        .onChange(of: people.undocumented) { _, _ in refilter() }
        .task { await people.run(in: app.database) }
    }

    private func refilter() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let next = trimmed.isEmpty
            ? people.undocumented
            : people.undocumented.filter { $0.person.name.localizedCaseInsensitiveContains(trimmed) }
        if visible != next { visible = next }
    }
}

/// `matchedTransitionSource` needs a namespace; this list borrows the one its parent list registered.
private struct ZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}
