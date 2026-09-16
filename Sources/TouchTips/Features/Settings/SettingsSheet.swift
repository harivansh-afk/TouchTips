import SwiftUI
import TouchTipsCore
import UserNotifications

struct SettingsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(PeopleLayout.key) private var peopleLayout = PeopleLayout.byDate
    @AppStorage("mapStyle") private var mapStyle = MapStyleChoice.muted
    @AppStorage("onboardingDone") private var onboardingDone = false
    @AppStorage(OnboardingAccess.pretendKey) private var pretendPending = false

    @State private var lastNotice: NoticeTiming?
    @State private var problem: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        AutomationSetupView()
                    } label: {
                        Label("Set up automatic checks", systemImage: "bolt.fill")
                    }
                    .accessibilityIdentifier("settings.automation")
                } header: {
                    Text("Automatic checks")
                } footer: {
                    Text("Use a Shortcuts automation to check contacts when you leave Contacts or Phone. No background location needed.")
                }

                Section {
                    accessRow("Contacts", status: contactsStatus) {
                        if app.contactsAccess.status == .notDetermined {
                            Task {
                                await app.contactsAccess.request()
                                app.capture.scheduleTick(.user)
                            }
                        } else {
                            openSettings()
                        }
                    }
                    accessRow("Location", status: locationStatus) {
                        if app.capture.locationPermissionAction == .request {
                            app.capture.requestLocation()
                        } else {
                            openSettings()
                        }
                    }
                    accessRow("Notifications", status: notificationsStatus) {
                        if app.notifier.status == .notDetermined {
                            Task { await app.notifier.request() }
                        } else {
                            openSettings()
                        }
                    }
                } header: {
                    Text("Access")
                } footer: {
                    Text("Tap a permission to change access in iOS Settings. Location is optional and only used when adding a place in TouchTips.")
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
                    Text("People page")
                } footer: {
                    Text(peopleLayout.detail)
                }

                Section("Map page") {
                    MapStyleGrid(choice: $mapStyle)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Text("Delete all data")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .tint(.red)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .disabled(app.capture.isResetting)
                    if let problem {
                        Text(problem).foregroundStyle(.secondary)
                    }
                }

                if BuildEnvironment.isDev {
                    Section {

                        if let lastNotice {
                            LabeledContent("Detection to submission", value: CaptureCoordinator.describe(lastNotice))
                        }
                    } header: {
                        Text("Dev")
                    } footer: {
                        Text(
                            "Notification timing starts at detection, not contact save. It measures submission, not banner presentation."
                        )
                    }

                    Section("Onboarding") {
                        Toggle("Replay with access pending", isOn: $pretendPending)
                        Button("Replay onboarding") {
                            HapticManager.medium()
                            onboardingDone = false
                            dismiss()
                        }
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
            .alert(
                "Delete everything TouchTips knows?",
                isPresented: $confirmDelete
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Delete all data", role: .destructive) {
                    HapticManager.warning()
                    Task { await deleteAll() }
                }
            } message: {
                Text("Contacts themselves are untouched. Meetings, visits and places are removed.")
            }
            .onChange(of: peopleLayout) { _, _ in HapticManager.selection() }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                app.contactsAccess.refresh()
                await app.notifier.refresh()
                await loadStats()
            }
        }
    }

    private var contactsStatus: String {
        switch app.contactsAccess.status {
        case .authorized: "Full"
        case .limited: "Limited"
        case .denied: "Off"
        case .restricted: "Restricted"
        case .notDetermined: "Allow"
        @unknown default: "Manage"
        }
    }

    private var locationStatus: String {
        switch app.capture.locationStatus {
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While Using"
        case .denied: "Off"
        case .restricted: "Restricted"
        case .notDetermined: "Allow"
        @unknown default: "Manage"
        }
    }

    private var notificationsStatus: String {
        if app.notifier.granted {
            return "On"
        }
        return app.notifier.status == .notDetermined ? "Allow" : "Off"
    }

    private func accessRow(_ title: String, status: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(status)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings-access-\(title.lowercased())")
        .accessibilityHint(status == "Allow" ? "Request permission" : "Change access in iOS Settings")
    }


    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    private func loadStats() async {
        guard BuildEnvironment.isDev else { return }
        do {
            let latency = try await app.database.reader.read { db in
                try db.value(for: .lastNotice).flatMap { try? NoticeTiming.decode($0) }
            }
            lastNotice = latency
        } catch {
            Log.ui.error("stats failed: \(error.localizedDescription)")
        }
    }

    private func deleteAll() async {
        do {
            try await app.capture.reset()
        } catch {
            HapticManager.error()
            problem = error.localizedDescription
        }
    }
}
