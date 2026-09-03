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
            Tab("People", systemImage: "person.2", value: .people) {
                PeopleView()
            }
            Tab("Map", systemImage: "map", value: .map) {
                MapScreen()
            }
            // The search role renders as the separated glass circle on the right. We borrow it for the one write action.
            Tab("Add", systemImage: "plus", value: .add, role: .search) {
                Color.black
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(.white)
        .onChange(of: tab) { previous, current in
            guard current == .add else { return }
            showAdd = true
            tab = previous
        }
        .sensoryFeedback(.selection, trigger: tab)
        .sheet(isPresented: $showAdd) {
            AddSheet()
        }
    }
}
