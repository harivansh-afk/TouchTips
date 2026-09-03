import SwiftUI

enum AppTab: Hashable {
    case people, map, search
}

struct RootView: View {
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var tab: AppTab = .people

    var body: some View {
        if onboardingDone {
            tabs
        } else {
            OnboardingView(done: $onboardingDone)
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
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
        .onChange(of: tab) { _, _ in
            // Haptic feedback on tab change
            HapticManager.selection()
        }
    }
}
