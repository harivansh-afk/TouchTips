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
    @AppStorage(PresencePolicy.key) private var presence = PresencePolicy.always
    @State private var stats: CaptureStats?
    @State private var lastNotice: NoticeTiming?
    @State private var problem: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Auto-capture location", isOn: Binding(
                        get: { app.capture.autoCaptureLocation },
                        set: {
                            app.capture.autoCaptureLocation = $0
                            HapticManager.selection()
                            if $0 {
                                app.capture.requestLocation()
                            }
                        }
                    ))
                    .tint(.blue)
                    if app.capture.autoCaptureLocation, !app.capture.locationGranted {
                        Button("Allow background location") {
                            switch app.capture.locationPermissionAction {
                            case .request: app.capture.requestLocation()
                            case .openSettings: openSettings()
                            case .allowed: break
                            }
                        }
                    }
                } header: {
                    Text("Preferences")
                } footer: {
                    Text(app.capture.autoCaptureLocation && !app.capture.locationGranted
                        ? "Choose Always in Settings to automatically capture location in the background."
                        : "Automatically remember where you meet people, even when TouchTips is in the background.")
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
                    Text("Tap a permission to change access in iOS Settings.")
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
                        // These diagnostics describe sampled execution, not continuous background availability.
                        Picker("Background location", selection: $presence) {
                            ForEach(PresencePolicy.allCases) { policy in
                                Text(policy.title).tag(policy)
                            }
                        }
                        .onChange(of: presence) { _, policy in app.capture.presencePolicy = policy }
                        if let stats {
                            LabeledContent("Scan coverage", value: Format.percent(stats.uptime))
                            LabeledContent("Wakes", value: wakesText(stats))
                            if let drain = stats.batteryPerHour {
                                LabeledContent(
                                    "Device battery",
                                    value: "\(drain.formatted(.number.precision(.fractionLength(1))))% per hour"
                                )
                            }
                        }
                        if let lastNotice {
                            LabeledContent("Detection to submission", value: CaptureCoordinator.describe(lastNotice))
                        }
                    } header: {
                        Text("Dev")
                    } footer: {
                        Text(
                            "Last 24 hours. Coverage samples app execution; battery measures the whole device. Notification timing starts at detection, not contact save."
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
                try (
                    Heartbeat.since(now.addingTimeInterval(-CaptureStats.span)).fetchAll(db),
                    db.value(for: .lastNotice).flatMap { try? NoticeTiming.decode($0) }
                )
            }
            stats = CaptureStats.make(from: beats, now: now)
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
