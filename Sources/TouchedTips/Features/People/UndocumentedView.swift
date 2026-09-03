import SwiftUI
import TouchedTipsCore

/// Everyone saved before TouchedTips, alphabetical. Tapping one opens the person screen, where a date can be set.
struct UndocumentedView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(\.zoomNamespace) private var zoom
    @State private var people = PeopleObserver()
    @State private var query = ""
    @State private var visible: [PersonRow] = []
    @FocusState private var focused: Bool
    @State private var hideHeader = false

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
                    .modifier(ZoomSource(id: row.id, namespace: zoom))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.ground)
        // No navigation bar, so a push from here animates nothing but the zoom. The title and
        // the field are content, like the roots.
        .toolbar(.hidden, for: .navigationBar)
        .hidesHeaderOnScroll($hideHeader)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Undocumented")
                    .font(.display(36))
                    .fixedSize()
                GlassSearchField(prompt: "Name", text: $query, focused: $focused)
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 8)
            .opacity(hideHeader ? 0 : 1)
            .allowsHitTesting(!hideHeader)
            .animation(.easeOut(duration: 0.15), value: hideHeader)
        }
        .scrollDismissesKeyboard(.immediately)
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
