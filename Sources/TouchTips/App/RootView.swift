import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var router = Router()
    /// Where the finished app is in coming into view. Settled from the start on a warm launch.
    @State private var arrival: ArrivalPhase
    /// The first-run screen stays over the app past `onboardingDone`, until its last glyph has left.
    @State private var showingOnboarding: Bool

    /// Content stops this far above the bottom safe area, so lists end above the capsule.
    private static let barInset = TabBar.height + TabBar.bottomPadding + 8 - 34

    init() {
        let done = UserDefaults.standard.bool(forKey: "onboardingDone")
        _arrival = State(initialValue: done ? .settled : .hidden)
        _showingOnboarding = State(initialValue: !done)
    }

    var body: some View {
        ZStack {
            tabs
                .environment(\.arrival, arrival)
                .allowsHitTesting(!showingOnboarding)
                .accessibilityHidden(showingOnboarding)
            if showingOnboarding {
                OnboardingView(finish: arrive)
                    // Above the app while it leaves; a removed view otherwise drops behind its siblings.
                    .zIndex(1)
                    // A replay fades in over the app. Leaving is the screen's own choreography.
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                app.contactsAccess.refresh()
                app.capture.foreground()
                // Contacts found while the app was away, by background refresh, get their place now.
                Task { await app.placeOnOpen.fill() }
                openNotification()
                Task { await app.cloud.checkApprovals() }
            }
        }
        .onChange(of: app.location.usable) { _, usable in
            if usable {
                Task { await app.placeOnOpen.fill() }
            }
        }
        .onChange(of: app.notifier.pendingPerson, initial: true) { _, _ in openNotification() }
        .onChange(of: onboardingDone) { _, done in
            if !done {
                replay()
            }
            openNotification()
        }
        .onChange(of: router.peopleReady) { _, _ in openNotification() }
        .onOpenURL { url in open(url) }
        .sheet(item: Bindable(router).connectRequest) { request in
            ConnectView(start: request.client)
                .environment(app)
        }
        .approvalSheet(app.cloud, active: !app.cloud.connectScreenOpen)
    }

    /// touchtips.app/connect/<client> opens Connect and starts that client; touchtips.app/p/<id> opens a person;
    /// touchtips://approve/<request> asks Allow for a client's sign-in.
    private func open(_ url: URL) {
        if url.scheme == "touchtips" {
            if url.host() == "approve", let id = url.pathComponents.last, id != "/" {
                Task { await app.cloud.checkApprovals(showing: id) }
            }
            return
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch (parts.first, parts.count) {
        case ("connect", 1):
            router.connectRequest = ConnectRequest(client: nil)
        case ("connect", 2):
            Log.ui.notice("connect link")
            router.connectRequest = ConnectRequest(client: ConnectClient.from(path: parts[1]))
        case ("p", 2):
            router.selectedTab = .people
            router.paths[.people] = [.person(parts[1], zoom: false)]
        default:
            break
        }
    }

    private func openNotification() {
        guard scenePhase == .active, onboardingDone, router.peopleReady,
              let contactID = app.notifier.pendingPerson else { return }
        Log.ui.notice("opening notification destination")
        router.openNotification(contactID)
        app.notifier.pendingPerson = nil
    }

    /// Continue was tapped and the first-run screen is on its way out. The app rises in under it
    /// while its last parts leave: header first, rows a beat apart, the bar from below, one tick
    /// as the header lands. The screen itself is removed once it has nothing left to draw.
    private func arrive() {
        // Remembered now, before the choreography: a crash mid-arrival must not replay the screen.
        onboardingDone = true
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            arrival = .arriving
            try? await Task.sleep(for: .milliseconds(250))
            HapticManager.light()
            try? await Task.sleep(for: .milliseconds(200))
            showingOnboarding = false
            try? await Task.sleep(for: .seconds(1))
            arrival = .settled
        }
    }

    /// The dev button in Settings: the screen comes back over the app, which hides under it at once.
    private func replay() {
        arrival = .hidden
        withAnimation(.easeInOut(duration: 0.3)) { showingOnboarding = true }
    }

    private var tabs: some View {
        @Bindable var router = router
        return ZStack(alignment: .bottom) {
            TabView(selection: $router.selectedTab) {
                Tab(value: .people) {
                    PeopleView()
                        // The root overlays our custom bar, so People must hide the system bar too.
                        .toolbarVisibility(.hidden, for: .tabBar)
                } label: {
                    Image(.users)
                }
                Tab(value: .map) {
                    LazyTab(tab: .map) { MapScreen() }
                } label: {
                    Image(.mapTrifold)
                }
                Tab(value: .search) {
                    LazyTab(tab: .search) { PeopleSearchView() }
                } label: {
                    Image(.magnifyingGlass)
                }
            }

            TabBar()
                .ignoresSafeArea(.keyboard)
                // One transform for the whole bar, not one per glyph.
                .geometryGroup()
                // Below the screen while the first-run screen is up, so its first frame in view is the rise.
                .offset(y: arrival == .hidden ? 140 : 0)
                .animation(
                    // Critically damped: the bar rises to its place and stops, no bounce past it.
                    arrival == .arriving ? .spring(response: 0.55, dampingFraction: 1).delay(0.1) : nil,
                    value: arrival == .hidden
                )
        }
        .tint(.white)
        .environment(router)
    }
}

/// expensive one; nobody pays for MapKit before asking for it.
private struct LazyTab<Content: View>: View {
    let tab: AppTab
    @ViewBuilder let content: () -> Content

    @Environment(Router.self) private var router
    @State private var hasBeenSelected = false

    var body: some View {
        Group {
            if hasBeenSelected {
                content()
            } else {
                Color.ground
            }
        }
        .toolbarVisibility(.hidden, for: .tabBar)
        .onAppear {
            if router.selectedTab == tab {
                hasBeenSelected = true
            }
        }
        .onChange(of: router.selectedTab) { _, selected in
            if selected == tab {
                hasBeenSelected = true
            }
        }
    }
}
