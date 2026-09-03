import SwiftUI
import TouchTipsCore

struct PeopleView: View {
    @Environment(AppModel.self) private var app
    @State private var rows: [PersonRow] = []
    @State private var path = NavigationPath()
    @State private var query = ""
    @State private var isSearchPresented = false
    @State private var showSettings = false
    @State private var hideToolbar = false
    @Namespace private var zoom

    private let revealThreshold: CGFloat = 90

    private var sections: [PeopleSection] { PeopleSections.make(from: rows, matching: query) }

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
                        Button {
                            HapticManager.light()
                            isSearchPresented = true
                        } label: {
                            Icon("magnifying-glass")
                        }
                        .accessibilityLabel("Search")
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
                .navigationDestination(for: String.self) { contactID in
                    PersonView(contactID: contactID)
                        .navigationTransition(.zoom(sourceID: contactID, in: zoom))
                }
                .sheet(isPresented: $showSettings) {
                    SettingsSheet()
                }
                .onChange(of: path.count) { _, _ in
                    HapticManager.selection()
                }
                .task { await observe() }
        }
    }

    private var content: some View {
        List {
            if sections.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            } else {
                ForEach(sections) { section in
                    Section {
                        let rows = section.rows.indexedRows()
                        ForEach(rows) { indexed in
                            let row = indexed.item
                            let index = indexed.index
                            NavigationLink(value: row.id) {
                                PersonRowView(row: row)
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowSeparatorTint(.white.opacity(0.12))
                            .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
                            .listRowSeparator(index == rows.count - 1 ? .hidden : .visible, edges: .bottom)
                            .matchedTransitionSource(id: row.id, in: zoom)
                        }
                    } header: {
                        HStack {
                            Text(section.title)
                            Spacer()
                            Text(section.rows.count, format: .number).foregroundStyle(.tertiary)
                        }
                        .font(.footnote.weight(.semibold))
                        .textCase(.uppercase)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .overlay {
            if rows.isEmpty {
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
        .onScrollPhaseChange { oldPhase, newPhase, context in
            guard oldPhase == .interacting, newPhase != .interacting else { return }
            let geometry = context.geometry
            let offset = geometry.contentOffset.y + geometry.contentInsets.top

            if offset < -revealThreshold && !isSearchPresented {
                isSearchPresented = true
                HapticManager.light()
            }
        }
        .searchable(text: $query, isPresented: $isSearchPresented, prompt: "Name or place")
    }

    private func observe() async {
        let observation = ValueObservation.tracking { db in try Person.rows().fetchAll(db) }
        do {
            for try await value in observation.values(in: app.database.reader) {
                if rows != value { rows = value }
            }
        } catch is CancellationError {
            // The view went away. Not an error.
        } catch {
            Log.ui.error("people observation ended: \(error.localizedDescription)")
        }
    }
}
