import SwiftUI

struct RootView: View {
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var router = Router()
    /// True from the end of onboarding until the tab bar has risen into place.
    @State private var barBelow = false

    /// Content stops this far above the bottom safe area, so lists end above the capsule.
    private static let barInset = TabBar.height + TabBar.bottomPadding + 8 - 34

    var body: some View {
        ZStack {
            if onboardingDone {
                tabs.transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                OnboardingView {
                    barBelow = true
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) { onboardingDone = true }
                }
                .transition(.opacity)
            }
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
                .onAppear { raiseBar() }
        }
        .tint(.white)
        .environment(router)
    }
}

extension RootView {
    /// After onboarding the bar arrives late, from below the screen, with a tick as it sets off.
    private func raiseBar() {
        guard barBelow else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(240))
            HapticManager.light()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { barBelow = false }
        }
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
