import GRDB
import SwiftUI
import TouchTipsCore

struct PeopleView: View {
    @Environment(AppModel.self) private var app
    @State private var rows: [PersonRow] = []
    @State private var query = ""
    @State private var showSettings = false
    @Namespace private var zoom

    private var sections: [PeopleSection] { PeopleSections.make(from: rows, matching: query) }

    private var subtitle: String {
        let placed = rows.filter { $0.place != nil }.count
        let before = rows.filter { $0.meet == nil }.count
        return "\(rows.count) people · \(placed) placed · \(before) before touchtips"
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.rows) { row in
                            NavigationLink(value: row.id) {
                                PersonRowView(row: row)
                            }
                            .listRowSeparatorTint(.white.opacity(0.12))
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
            .navigationTitle("People")
            .navigationSubtitle(subtitle)
            .searchable(text: $query, prompt: "Name or place")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                }
            }
            .navigationDestination(for: String.self) { contactID in
                PersonView(contactID: contactID)
                    .navigationTransition(.zoom(sourceID: contactID, in: zoom))
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet()
            }
            .task { await observe() }
        }
    }

    private func observe() async {
        let observation = ValueObservation.tracking { db in try Person.rows().fetchAll(db) }
        do {
            for try await value in observation.values(in: app.database.reader) {
                rows = value
            }
        } catch {
            Log.ui.error("people observation ended: \(error.localizedDescription)")
        }
    }
}
