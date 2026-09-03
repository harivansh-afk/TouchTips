import SwiftUI
import TouchTipsCore

struct PeopleView: View {
    @Environment(AppModel.self) private var app
    @State private var people = PeopleObserver()
    @State private var path = NavigationPath()
    @State private var showAdd = false
    @State private var showSettings = false
    @State private var hideToolbar = false

    private var sections: [PeopleSection] { PeopleSections.make(from: people.rows) }

    var body: some View {
        NavigationStack(path: $path) {
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
                                Icon("plus")
                            }
                            .accessibilityLabel("Add")
                        }
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                HapticManager.light()
                                showSettings = true
                            } label: {
                                Icon("gear-six")
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
                .onChange(of: path.count) { _, _ in
                    HapticManager.selection()
                }
                .task { await people.run(in: app.database) }
        }
    }

    private var content: some View {
        PeopleList(sections: sections)
            .overlay {
                if people.rows.isEmpty {
                    ContentUnavailableView(
                        "No one yet",
                        systemImage: "person.2",
                        description: Text("New contacts show up here with when and where you met.")
                    )
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
}
