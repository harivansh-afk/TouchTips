import SwiftUI
import TouchedTipsCore

struct SettingsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage(PeopleLayout.key) private var peopleLayout = PeopleLayout.byDate
    @AppStorage("mapStyle") private var mapStyle = MapStyleChoice.muted
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var problem: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Access") {
                    LabeledContent("Contacts") {
                        if app.contactsAccess.granted {
                            Text("Full")
                        } else {
                            Button("Allow") {
                                Task {
                                    await app.contactsAccess.request()
                                    app.capture.scheduleTick()
                                }
                            }
                        }
                    }
                    LabeledContent("Location") {
                        if app.capture.locationGranted {
                            Text("Always")
                        } else if app.capture.locationStatus == .denied || app.capture.locationStatus == .restricted {
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    openURL(url)
                                }
                            }
                        } else {
                            Button("Allow") { app.capture.requestLocation() }
                        }
                    }
                }

                Section {
                    Picker("Layout", selection: $peopleLayout) {
                        ForEach(PeopleLayout.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("People")
                } footer: {
                    Text(peopleLayout.detail)
                }

                Section("Map") {
                    MapStyleGrid(choice: $mapStyle)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                Section {
                    Button("Delete all data", role: .destructive) { confirmDelete = true }
                    if let problem {
                        Text(problem).foregroundStyle(.secondary)
                    }
                }

                if BuildEnvironment.isDev {
                    Section {
                        Button("Replay onboarding") {
                            HapticManager.medium()
                            onboardingDone = false
                            dismiss()
                        }
                    } header: {
                        Text("Dev")
                    } footer: {
                        Text("Debug and TestFlight builds only.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            // Into the keyboard region too, or the translucent keyboard shows a hard edge where the black stops.
            .background { Color.ground.ignoresSafeArea() }
            .serifTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        HapticManager.light()
                        dismiss()
                    } label: {
                        Icon(.check)
                    }
                    .accessibilityLabel("Done")
                }
            }
            .confirmationDialog(
                "Delete everything TouchedTips knows?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete all data", role: .destructive) {
                    HapticManager.warning()
                    deleteAll()
                }
            } message: {
                Text("Contacts themselves are untouched. Meetings, visits and places are removed.")
            }
            .onChange(of: peopleLayout) { _, _ in HapticManager.selection() }
            .onAppear { app.contactsAccess.refresh() }
        }
    }

    private func deleteAll() {
        do {
            try Ingest.deleteAll(app.database)
            app.capture.scheduleTick()
        } catch {
            HapticManager.error()
            problem = error.localizedDescription
        }
    }
}
