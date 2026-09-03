import SwiftUI

enum AppTab: Hashable {
    case people, map, add
}

struct RootView: View {
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var tab: AppTab = .people
    @State private var showAdd = false

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
            // The search role renders as the separated glass circle on the right. We borrow it for the one write action.
            Tab(value: .add, role: .search) {
                Color.black
            } label: {
                Image("plus")
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(.white)
        .onChange(of: tab) { previous, current in
            // Haptic feedback on tab change. Skipped for the bounce back from the plus slot.
            if previous != .add { HapticManager.selection() }
            guard current == .add else { return }
            showAdd = true
            tab = previous
        }
        .sheet(isPresented: $showAdd) {
            AddSheet()
        }
    }
}
