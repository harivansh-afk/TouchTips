import SwiftUI

struct RootView: View {
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var router = Router()
    /// True until onboarding has finished and the tab bar has risen into place. The tabs are
    /// built underneath onboarding from launch, so the hand-over animates layers that already
    /// exist instead of paying for their first layout mid-animation.
    @State private var barBelow = !UserDefaults.standard.bool(forKey: "onboardingDone")

    /// Content stops this far above the bottom safe area, so lists end above the capsule.
    private static let barInset = TabBar.height + TabBar.bottomPadding + 8 - 34

    var body: some View {
        ZStack {
            tabs
                .opacity(onboardingDone ? 1 : 0)
                .scaleEffect(onboardingDone ? 1 : 0.96)
                .allowsHitTesting(onboardingDone)
                .accessibilityHidden(!onboardingDone)
            if !onboardingDone {
                OnboardingView { arrive() }
                    .transition(.opacity)
            }
        }
        // Replaying onboarding from Settings puts the bar back below for the next arrival.
        .onChange(of: onboardingDone) { _, done in
            if !done {
                barBelow = true
            }
        }
    }

    /// The app settles in from slightly small; the bar follows from below the screen, with a tick.
    private func arrive() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { onboardingDone = true }
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            HapticManager.light()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { barBelow = false }
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
                .offset(y: barBelow ? 140 : 0)
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
