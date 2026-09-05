import SwiftUI
import TouchTipsCore

/// The search tab. The list alone until the search button is tapped; then a glass field appears at
/// the top with the keyboard up. It goes away again when the keyboard drops with nothing typed.
struct PeopleSearchView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @State private var people = PeopleObserver()
    @Namespace private var zoom
    @State private var query = ""
    @State private var groups = PeopleGroups()
    @State private var hideHeader = false
    @State private var showField = false
    /// The last request this view acted on. The tab is built lazily, so the first request can
    /// land before the view exists; comparing counts on appear catches it.
    @State private var handledRequests = 0
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack(path: router.path(for: .search)) {
            PeopleList(
                sections: groups.sections,
                undocumented: groups.undocumented,
                expandUndocumented: true,
                query: query
            )
            .environment(\.zoomNamespace, zoom)
            .navigationDestination(for: Destination.self) { destination in
                DestinationView(destination: destination, zoom: zoom)
            }
            .aboveTabBar()
            .toolbar(.hidden, for: .navigationBar)
            .scrollDismissesKeyboard(.immediately)
            .hidesHeaderOnScroll($hideHeader)
            .minimizesTabBarOnScroll()
            .safeAreaInset(edge: .top, spacing: 0) {
                if showField {
                    GlassSearchField(prompt: "Name, place or note", text: $query, focused: $focused)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                        .opacity(hideHeader ? 0 : 1)
                        .allowsHitTesting(!hideHeader)
                        .animation(.easeOut(duration: 0.15), value: hideHeader)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onChange(of: router.searchRequests, initial: true) { _, count in
                guard count > handledRequests else { return }
                handledRequests = count
                hideHeader = false
                withAnimation(.appleMusic) { showField = true }
                focusWhenReady()
            }
            .onChange(of: focused) { _, focused in
                guard !focused, query.isEmpty else { return }
                // Let the keyboard finish leaving before the field does, or the two fight and the list jitters.
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !self.focused, query.isEmpty else { return }
                    withAnimation(.appleMusic) { showField = false }
                }
            }
            .onChange(of: query) { _, _ in regroup() }
            .onChange(of: people.rows) { _, _ in regroup() }
            .onChange(of: router.paths[.search]?.count) { _, _ in
                HapticManager.selection()
            }
            .task { await people.run(in: app.database) }
        }
    }

    /// The field has to exist before it can take focus. Ask a few times over the first frames;
    /// the first that lands wins, the rest are no-ops.
    private func focusWhenReady() {
        Task {
            for _ in 0 ..< 6 {
                focused = true
                try? await Task.sleep(for: .milliseconds(40))
                if focused {
                    return
                }
            }
        }
    }

    private func regroup() {
        let next = PeopleSections.make(from: people.rows, matching: query)
        if groups != next {
            groups = next
        }
    }
}
