import SwiftUI

struct RootView: View {
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var router = Router()
    /// True from the end of onboarding until the tab bar has risen into place.
    @State private var arriving = false

    /// Content stops this far above the bottom safe area, so lists end above the capsule.
    private static let barInset = TabBar.height + TabBar.bottomPadding + 8 - 34

    /// The app is built and laid out under onboarding from launch and is never itself animated:
    /// glass loses its backdrop under an animated ancestor and snaps back when the animation
    /// ends. Only the onboarding overlay fades, and the bar moves by a transform.
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
                    LazyTab(tab: .people) { PeopleView() }
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: Self.barInset)
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
