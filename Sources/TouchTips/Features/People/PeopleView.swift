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
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .fixedSize()
                            .padding(.leading, -4)
                            .opacity(hideToolbar ? 0 : 1)
                    }
                    .sharedBackgroundVisibility(.hidden)

                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 10) {
                            GlassCircleButton(icon: "plus", label: "Add") {
                                HapticManager.light()
                                showAdd = true
                            }
                            GlassCircleButton(icon: "gear-six", label: "Settings") {
                                HapticManager.light()
                                showSettings = true
                            }
                        }
                        .opacity(hideToolbar ? 0 : 1)
                    }
                    .sharedBackgroundVisibility(.hidden)
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
