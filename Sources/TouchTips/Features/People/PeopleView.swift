import SwiftUI
import TouchTipsCore

struct PeopleView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @State private var people = PeopleObserver()
    @State private var showAdd = false
    @State private var showSettings = false
    @State private var hideToolbar = false

    var body: some View {
        NavigationStack(path: router.path(for: .people)) {
            content
                .navigationBarTitleDisplayMode(.inline)
                .contentMargins(.top, 0, for: .scrollContent)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Text("People")
                            .font(.display(36))
                            .fixedSize()
                            .padding(.leading, -4)
                            .opacity(hideToolbar ? 0 : 1)
                    }
                    .sharedBackgroundVisibility(.hidden)

                    // Native glass circles, so size and spacing are the system's. They leave the bar on scroll.
                    if !hideToolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                HapticManager.light()
                                showAdd = true
                            } label: {
                                Icon(.plus)
                            }
                            .accessibilityLabel("Add")
                        }
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                HapticManager.light()
                                showSettings = true
                            } label: {
                                Icon(.gearSix)
                            }
                            .accessibilityLabel("Settings")
                        }
                    }
                }
                .sheet(isPresented: $showAdd) {
                    AddSheet()
                }
                .sheet(isPresented: $showSettings) {
                    SettingsSheet()
                }
                .onChange(of: router.paths[.people]?.count) { _, _ in
                    HapticManager.selection()
                }
                .task { await people.run(in: app.database) }
        }
    }

    private var content: some View {
        PeopleList(sections: people.sections, undocumented: people.undocumented)
            .overlay {
                if people.rows.isEmpty {
                    emptyState
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newValue in
                let shouldHide = newValue > 0
                if shouldHide != hideToolbar {
                    withAnimation(.easeOut(duration: 0.15)) {
                        hideToolbar = shouldHide
                    }
                }
            }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch people.readiness {
        case .contactsOff:
            ContentUnavailableView(
                "Contacts is off",
                systemImage: "person.crop.circle.badge.xmark",
                description: Text("Nothing can be noticed until touchtips can read your contacts. Allow it in Settings.")
            )
        case .reading:
            ContentUnavailableView {
                Label {
                    Text("Reading your contacts")
                } icon: {
                    ProgressView()
                }
            } description: {
                Text("The first read goes through everyone once.")
            }
        case .ready:
            ContentUnavailableView(
                "No one yet",
                systemImage: "person.2",
                description: Text("New contacts show up here with when and where you met.")
            )
        }
    }
}
