import SwiftUI
import TouchedTipsCore

/// The search tab. The list alone until the search button is tapped; then a glass field appears at
/// the top with the keyboard up. It goes away again when the keyboard drops with nothing typed.
struct PeopleSearchView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @State private var people = PeopleObserver()
    @State private var query = ""
    @State private var groups = PeopleGroups()
    @State private var hideHeader = false
    @State private var showField = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack(path: router.path(for: .search)) {
            PeopleList(sections: groups.sections, undocumented: groups.undocumented, expandUndocumented: true, query: query)
                .toolbar(.hidden, for: .navigationBar)
                .scrollDismissesKeyboard(.immediately)
                .hidesHeaderOnScroll($hideHeader)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if showField {
                        field
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                            .opacity(hideHeader ? 0 : 1)
                            .allowsHitTesting(!hideHeader)
                            .animation(.easeOut(duration: 0.15), value: hideHeader)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .onChange(of: router.searchRequests) { _, _ in
                    withAnimation(.appleMusic) { showField = true }
                    // The field has to exist before it can take focus; one tick is enough.
                    Task {
                        try? await Task.sleep(for: .milliseconds(50))
                        focused = true
                    }
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
