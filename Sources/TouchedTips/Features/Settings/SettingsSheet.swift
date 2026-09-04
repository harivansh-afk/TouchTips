import SwiftUI
import TouchedTipsCore
import UserNotifications

struct SettingsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage(PeopleLayout.key) private var peopleLayout = PeopleLayout.byDate
    @AppStorage("mapStyle") private var mapStyle = MapStyleChoice.muted
    @AppStorage("onboardingDone") private var onboardingDone = false
    @AppStorage(PresencePolicy.key) private var presence = PresencePolicy.always
    @State private var stats: CaptureStats?
    @State private var lastNotice: NoticeTiming?
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
                                    app.capture.scheduleTick(.user)
                                }
                            }
                        }
                    }
                    LabeledContent("Location") {
                        if app.capture.locationGranted {
                            Text("Always")
                        } else if app.capture.locationStatus == .denied || app.capture.locationStatus == .restricted {
                            Button("Open Settings", action: openSettings)
                        } else {
                            Button("Allow") { app.capture.requestLocation() }
                        }
                    }
                    LabeledContent("Notifications") {
                        if app.notifier.granted {
                            Text("On")
                        } else if app.notifier.status == .denied {
                            Button("Open Settings", action: openSettings)
                        } else {
                            Button("Allow") { Task { await app.notifier.request() } }
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
                        // Stays here until a week of numbers picks the default. Awake, an add is heard the moment it is saved.
                        Picker("Stay awake", selection: $presence) {
                            ForEach(PresencePolicy.allCases) { policy in
                                Text(policy.title).tag(policy)
                            }
                        }
                        .onChange(of: presence) { _, policy in app.capture.presencePolicy = policy }
                        if let stats {
                            LabeledContent("Awake", value: Format.percent(stats.uptime))
                            LabeledContent("Wakes", value: wakesText(stats))
                            if let drain = stats.batteryPerHour {
                                LabeledContent("Battery", value: "\(drain.formatted(.number.precision(.fractionLength(1))))% per hour")
                            }
                        }
                        if let lastNotice {
                            LabeledContent("Last notice", value: CaptureCoordinator.describe(lastNotice))
                        }
                        Button("Replay onboarding") {
                            HapticManager.medium()
                            onboardingDone = false
                            dismiss()
                        }
                    } header: {
                        Text("Dev")
                    } footer: {
                        Text("Last 24 hours. Debug and TestFlight builds only.")
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
            .task {
                await app.notifier.refresh()
                await loadStats()
            }
        }
    }

    private func wakesText(_ stats: CaptureStats) -> String {
        stats.wakes.isEmpty ? "None" : stats.wakes.map { "\($0.source.rawValue) \($0.count)" }.joined(separator: ", ")
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    private func loadStats() async {
        guard BuildEnvironment.isDev else { return }
        let now = Date()
        do {
            let (beats, latency) = try await app.database.reader.read { db in
                (
                    try Heartbeat.since(now.addingTimeInterval(-CaptureStats.span)).fetchAll(db),
                    try db.value(for: .lastNotice).flatMap { try? NoticeTiming.decode($0) }
                )
            }
            stats = CaptureStats.make(from: beats, now: now)
            lastNotice = latency
        } catch {
            Log.ui.error("stats failed: \(error.localizedDescription)")
        }
    }

    private func deleteAll() {
        do {
            try Ingest.deleteAll(app.database)
            app.capture.scheduleTick(.user)
        } catch {
            HapticManager.error()
            problem = error.localizedDescription
        }
    }
}
