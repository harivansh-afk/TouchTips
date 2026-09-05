import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var router = Router()
    /// True from the end of onboarding until the tab bar has risen into place.
    @State private var arriving = false

    /// Content stops this far above the bottom safe area, so lists end above the capsule.
    private static let barInset = TabBar.height + TabBar.bottomPadding + 8 - 34

    var body: some View {
        ZStack {
            tabs
                .allowsHitTesting(onboardingDone)
                .accessibilityHidden(!onboardingDone)
            if !onboardingDone {
                OnboardingView { arrive() }
                    .transition(.opacity)
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                app.contactsAccess.refresh()
                app.capture.scheduleTick(.foreground)
                app.geocoder.kick()
                openNotification()
            }
        }
        .onChange(of: app.notifier.pendingPerson, initial: true) { _, _ in openNotification() }
        .onChange(of: onboardingDone) { _, _ in openNotification() }
        .onChange(of: router.peopleReady) { _, _ in openNotification() }
    }

    private func openNotification() {
        guard scenePhase == .active, onboardingDone, router.peopleReady,
              let contactID = app.notifier.pendingPerson else { return }
        Log.ui.notice("opening notification destination")
        router.openNotification(contactID)
        app.notifier.pendingPerson = nil
    }

    /// The overlay fades to reveal the finished app; the bar follows from below, with a tick.
    /// The bar drops below the screen first, unanimated and still covered, so its first frame in
    /// view is the rise.
    private func arrive() {
        arriving = true
        withAnimation(.easeInOut(duration: 0.45)) { onboardingDone = true }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            HapticManager.light()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { arriving = false }
        }
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
                .offset(y: arriving ? 140 : 0)
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
