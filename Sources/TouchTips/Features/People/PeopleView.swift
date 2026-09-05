import SwiftUI
import TouchTipsCore

struct PeopleView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @AppStorage(PeopleLayout.key) private var layout = PeopleLayout.byDate
    @State private var people = PeopleObserver()
    @State private var showAdd = false
    @State private var showSettings = false
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
                .onAppear { router.peopleReady = true }
                .onChange(of: router.notificationRequest) { _, _ in
                    showAdd = false
                    showSettings = false
                }
        }
    }

    private var content: some View {
        ScrollViewReader { proxy in
            list
                .aboveTabBar()
                .hidesHeaderOnScroll($hideHeader)
                .minimizesTabBarOnScroll()
                .overlay {
                    if people.rows.isEmpty {
                        emptyState
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
        switch layout {
        case .byDate: people.sections.first?.id
        case .timeline: people.timeline.first?.id
        case .byPlace: people.placeSections.first?.id
        }
    }

    /// The layout Settings chose. The change happens under the Settings sheet, so nothing animates.
    @ViewBuilder
    private var list: some View {
        switch layout {
        case .byDate:
            PeopleList(sections: people.sections, undocumented: people.undocumented)
        case .timeline:
            PeopleTimeline(items: people.timeline, undocumented: people.undocumented)
        case .byPlace:
            PeopleList(sections: people.placeSections, undocumented: people.undocumented, showsPlace: false)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch people.readiness {
        case .contactsOff:
            ContentUnavailableView(
                "Contacts is off",
                systemImage: "person.crop.circle.badge.xmark",
                description: Text(
                    "Allow Contacts access in Settings."
                )
            )
        case .reading:
            ContentUnavailableView {
                Label {
                    Text("Reading your contacts")
                } icon: {
                    ProgressView()
                }
            }
        case .ready:
            ContentUnavailableView(
                "No one yet",
                systemImage: "person.2",
                description: Text("New contacts will appear here.")
            )
        }
    }
}
