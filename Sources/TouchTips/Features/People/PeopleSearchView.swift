import SwiftUI
import TouchTipsCore

/// The search tab. A glass field at the top that takes focus when the tab is selected and fades
/// away as the list scrolls, over the same month-grouped list.
struct PeopleSearchView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @State private var people = PeopleObserver()
    @State private var query = ""
    @State private var groups = PeopleGroups()
    @State private var hideHeader = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack(path: router.path(for: .search)) {
            PeopleList(sections: groups.sections, undocumented: groups.undocumented, expandUndocumented: true, query: query)
                .toolbar(.hidden, for: .navigationBar)
                .scrollDismissesKeyboard(.immediately)
                .hidesHeaderOnScroll($hideHeader)
                .safeAreaInset(edge: .top, spacing: 0) {
                    field
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                        .opacity(hideHeader ? 0 : 1)
                        .allowsHitTesting(!hideHeader)
                        .animation(.easeOut(duration: 0.15), value: hideHeader)
                }
                .onChange(of: router.selectedTab, initial: true) { _, tab in
                    if tab == .search { focused = true }
                }
                .onChange(of: query) { _, _ in regroup() }
                .onChange(of: people.rows) { _, _ in regroup() }
                .onChange(of: router.paths[.search]?.count) { _, _ in
                    HapticManager.selection()
                }
                .task { await people.run(in: app.database) }
        }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Icon(.magnifyingGlass, size: 18)
                .foregroundStyle(.secondary)
            TextField("Name or place", text: $query)
                .focused($focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    HapticManager.light()
                    query = ""
                } label: {
                    Icon(.x, size: 16)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .glassEffect(.clear, in: .capsule)
    }

    private func regroup() {
        let next = PeopleSections.make(from: people.rows, matching: query)
        if groups != next { groups = next }
    }
}
