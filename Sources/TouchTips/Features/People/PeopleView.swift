import SwiftUI
import TouchTipsCore

struct PeopleView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @State private var people = PeopleObserver()
    @State private var showAdd = false
    @State private var showSettings = false
    @State private var showConnect = false
    @State private var hideHeader = false
    @Namespace private var zoom

    var body: some View {
        NavigationStack(path: router.path(for: .people)) {
            content
                .environment(\.zoomNamespace, zoom)
                .navigationDestination(for: Destination.self) { destination in
                    DestinationView(destination: destination, zoom: zoom)
                }
                // No navigation bar on a root: a push then animates nothing but the zoom.
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    ScreenHeader(title: "People", hidden: hideHeader) {
                        HeaderButtons {
                            HeaderButton(glyph: .plugs, label: "Connect") { showConnect = true }
                            HeaderButton(glyph: .gearSix, label: "Settings") { showSettings = true }
                        }
                    }
                    .arrives(order: 0)
                }
                .sheet(isPresented: $showAdd) {
                    AddSheet()
                }
                .sheet(isPresented: $showSettings) {
                    SettingsSheet()
                }
                .sheet(isPresented: $showConnect) {
                    ConnectView()
                }
                .onChange(of: router.paths[.people]?.count) { _, _ in
                    HapticManager.selection()
                }
                .task { await people.run(in: app.database) }
                .onAppear { router.peopleReady = true }
                .onChange(of: router.notificationRequest) { _, _ in
                    showAdd = false
                    showSettings = false
                }
                .onChange(of: router.connectRequest) { _, request in
                    guard request != nil else { return }
                    showAdd = false
                    showSettings = false
                    showConnect = false
                }
        }
    }

    private var content: some View {
        ScrollViewReader { proxy in
            list
                .aboveTabBar()
                .hidesHeaderOnScroll($hideHeader)
                .minimizesTabBarOnScroll()
                .pullsDownToAdd { showAdd = true }
                .overlay {
                    if people.rows.isEmpty {
                        emptyState.arrives(order: 1)
                    }
                }
                .onChange(of: router.scrollToTop[.people, default: 0]) { _, _ in
                    guard let topScrollID else { return }
                    withAnimation(.appleMusic) {
                        proxy.scrollTo(topScrollID, anchor: .top)
                    }
                }
        }
    }

    private var topScrollID: String? {
        people.timeline.first?.id
    }

    /// Everyone on one line. The one layout the tab has; search keeps the plain list.
    private var list: some View {
        PeopleTimeline(items: people.timeline, undocumented: people.undocumented)
    }

    @ViewBuilder
    private var emptyState: some View {
        switch people.readiness {
        case .contactsOff:
            EmptyNote(title: "Contacts is off", detail: "Allow Contacts access in Settings.")
        case .reading:
            EmptyNote(title: "Reading your contacts", busy: true)
        case .ready:
            EmptyNote(title: "No one yet", detail: "Pull down to add someone you just met.")
        }
    }
}
