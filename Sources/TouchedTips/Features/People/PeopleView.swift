import SwiftUI
import TouchedTipsCore

struct PeopleView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @State private var people = PeopleObserver()
    @State private var showAdd = false
    @State private var showSettings = false
    @State private var hideHeader = false

    var body: some View {
        NavigationStack(path: router.path(for: .people)) {
            content
                // No navigation bar on a root: a push then animates nothing but the zoom.
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    ScreenHeader(title: "People", hidden: hideHeader) {
                        HeaderButtons {
                            HeaderButton(glyph: .plus, label: "Add") { showAdd = true }
                            HeaderButton(glyph: .gearSix, label: "Settings") { showSettings = true }
                        }
                    }
                }
                .sheet(isPresented: $showAdd) {
                    AddSheet()
                }
                .sheet(isPresented: $showSettings) {
                    SettingsSheet()
                }
                .onChange(of: router.paths[.people]?.count) { _, _ in
                    HapticManager.selection()
                }
                .task { await people.run(in: app.database) }
        }
    }

    private var content: some View {
        PeopleList(sections: people.sections, undocumented: people.undocumented)
            .hidesHeaderOnScroll($hideHeader)
            .overlay {
                if people.rows.isEmpty {
                    emptyState
                }
            }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch people.readiness {
        case .contactsOff:
            ContentUnavailableView(
                "Contacts is off",
                systemImage: "person.crop.circle.badge.xmark",
                description: Text("Nothing can be noticed until TouchedTips can read your contacts. Allow it in Settings.")
            )
        case .reading:
            ContentUnavailableView {
                Label {
                    Text("Reading your contacts")
                } icon: {
                    ProgressView()
                }
            } description: {
                Text("The first read goes through everyone once.")
            }
        case .ready:
            ContentUnavailableView(
                "No one yet",
                systemImage: "person.2",
                description: Text("New contacts show up here with when and where you met.")
            )
        }
    }
}
