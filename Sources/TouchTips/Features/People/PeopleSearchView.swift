import SwiftUI
import TouchTipsCore

/// The search tab. The field lives in the navigation bar and takes focus when the tab is selected.
struct PeopleSearchView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @State private var people = PeopleObserver()
    @State private var query = ""
    @State private var isSearchPresented = false
    @State private var groups = PeopleGroups()

    var body: some View {
        NavigationStack(path: router.path(for: .search)) {
            PeopleList(sections: groups.sections, undocumented: groups.undocumented, expandUndocumented: true, query: query)
                .navigationBarTitleDisplayMode(.inline)
                .contentMargins(.top, 0, for: .scrollContent)
                .searchable(
                    text: $query, isPresented: $isSearchPresented,
                    placement: .navigationBarDrawer(displayMode: .always), prompt: "Name or place"
                )
                .onChange(of: router.selectedTab, initial: true) { _, tab in
                    if tab == .search { isSearchPresented = true }
                }
                .onChange(of: query) { _, _ in regroup() }
                .onChange(of: people.rows) { _, _ in regroup() }
                .onChange(of: router.paths[.search]?.count) { _, _ in
                    HapticManager.selection()
                }
                .task { await people.run(in: app.database) }
        }
    }

    private func regroup() {
        let next = PeopleSections.make(from: people.rows, matching: query)
        if groups != next { groups = next }
    }
}
