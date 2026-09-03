import SwiftUI
import TouchTipsCore

/// The search tab. The tab bar itself becomes the field; this is what sits above it.
struct PeopleSearchView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @State private var people = PeopleObserver()
    @State private var query = ""
    @State private var isSearchPresented = false

    private var sections: [PeopleSection] { PeopleSections.make(from: people.rows, matching: query) }

    var body: some View {
        NavigationStack(path: router.path(for: .search)) {
            PeopleList(sections: sections, query: query)
                .navigationBarTitleDisplayMode(.inline)
                .contentMargins(.top, 0, for: .scrollContent)
                .searchable(
                    text: $query, isPresented: $isSearchPresented,
                    placement: .navigationBarDrawer(displayMode: .always), prompt: "Name or place"
                )
                .onChange(of: router.selectedTab, initial: true) { _, tab in
                    if tab == .search { isSearchPresented = true }
                }
                .onChange(of: router.paths[.search]?.count) { _, _ in
                    HapticManager.selection()
                }
                .task { await people.run(in: app.database) }
        }
    }
}
