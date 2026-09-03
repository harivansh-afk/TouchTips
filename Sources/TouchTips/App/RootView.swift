import SwiftUI

struct RootView: View {
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var router = Router()

    /// Content stops this far above the bottom safe area, so lists end above the capsule.
    private static let barInset = TabBar.height + TabBar.bottomPadding + 8 - 34

    var body: some View {
        if onboardingDone {
            tabs
        } else {
            OnboardingView(done: $onboardingDone)
        }
    }

    private var tabs: some View {
        @Bindable var router = router
        return ZStack(alignment: .bottom) {
            TabView(selection: $router.selectedTab) {
                Tab(value: .people) {
                    LazyTab(tab: .people) { PeopleView() }
                } label: {
                    Image("users")
                }
                Tab(value: .map) {
                    LazyTab(tab: .map) { MapScreen() }
                } label: {
                    Image("map-trifold")
                }
                Tab(value: .search) {
                    LazyTab(tab: .search) { PeopleSearchView() }
                } label: {
                    Image("magnifying-glass")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: Self.barInset)
            }

            TabBar()
                .ignoresSafeArea(.keyboard)
        }
        .tint(.white)
        .environment(router)
    }
}

/// Builds a tab's content the first time it is selected, the way phia does. The map is the
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
                Color.black
            }
        }
        .toolbarVisibility(.hidden, for: .tabBar)
        .onAppear { if router.selectedTab == tab { hasBeenSelected = true } }
        .onChange(of: router.selectedTab) { _, selected in
            if selected == tab { hasBeenSelected = true }
        }
    }
}
