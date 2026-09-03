import SwiftUI

struct RootView: View {
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var router = Router()

    var body: some View {
        if onboardingDone {
            tabs
        } else {
            OnboardingView(done: $onboardingDone)
        }
    }

    private var tabs: some View {
        @Bindable var router = router
        return TabView(selection: $router.selectedTab) {
            Tab(value: .people) {
                PeopleView()
            } label: {
                Image("users")
            }
            Tab(value: .map) {
                MapScreen()
            } label: {
                Image("map-trifold")
            }
            // The search role is the separated glass circle on the right; the bar becomes the field.
            Tab(value: .search, role: .search) {
                PeopleSearchView()
            } label: {
                Image("magnifying-glass")
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewSearchActivation(.searchTabSelection)
        .tint(.white)
        .environment(router)
        .onChange(of: router.selectedTab) { _, _ in
            // Haptic feedback on tab change
            HapticManager.selection()
        }
    }
}
