import SwiftUI
import TouchTipsCore
import UserNotifications

/// Settings as the app draws its other sheets: a caption over each group, the group one glass card
/// with hairlines between its rows, the way the Add sheet draws name and phone. No system Form.
struct SettingsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("mapStyle") private var mapStyle = MapStyleChoice.muted
    @AppStorage("onboardingDone") private var onboardingDone = false
    @AppStorage(OnboardingAccess.pretendKey) private var pretendPending = false
    @State private var lastNotice: NoticeTiming?
    @State private var problem: String?
    @State private var confirmDelete = false
    @State private var showConnected = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    group("Access", footer: "Tap a permission to change access in iOS Settings.") {
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
                        hairline
                        accessRow("Notifications", status: notificationsStatus) {
                            if app.notifier.status == .notDetermined {
                                Task { await app.notifier.request() }
                            } else {
                                openSettings()
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Map page").padding(.leading, 6)
                        MapStyleGrid(choice: $mapStyle)
                    }

                    group("AI", footer: "Let Claude, ChatGPT or any MCP client ask when and where you met someone.") {
                        accessRow("Connected apps", status: app.cloud.clients.isEmpty ? "None" : "\(app.cloud.clients.count)") {
                            showConnected = true
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Text("Delete all data")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .tint(.red)
                        .disabled(app.capture.isResetting)
                        if let problem {
                            Text(problem)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                        }
                    }

                    if BuildEnvironment.isDev {
                        dev
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            // Into the keyboard region too, or the translucent keyboard shows a hard edge where the black stops.
            .background { Color.ground.ignoresSafeArea() }
            .serifTitle("Settings")
            .navigationDestination(isPresented: $showConnected) {
                ConnectedAppsView()
            }
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
                Text("Contacts themselves are untouched. Meetings, notes and places are removed.")
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                app.contactsAccess.refresh()
                await app.notifier.refresh()
                await loadLastNotice()
            }
        }
    }

    // MARK: - Groups

    private func group(_ title: String, footer: String? = nil, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: title).padding(.leading, 6)
            VStack(spacing: 0) {
                rows()
            }
            .glassEffect(.clear, in: .rect(cornerRadius: 22))
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 1)
            .padding(.leading, 18)
    }

    private func accessRow(_ title: String, status: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(status)
                    .foregroundStyle(.secondary)
                Icon(.caretRight, size: 14)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .contentShape(.rect)
        }
        .buttonStyle(.press)
        .accessibilityIdentifier("settings-access-\(title.lowercased())")
        .accessibilityHint(status == "Allow" ? "Request permission" : "Change access in iOS Settings")
    }

    @ViewBuilder
    private var dev: some View {
        if let lastNotice {
            group("Dev", footer: "Notification timing starts at detection, not contact save.") {
                HStack {
                    Text("Detection to submission")
                    Spacer()
                    Text(CaptureCoordinator.describe(lastNotice))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 15)
            }
        }
        group("Onboarding") {
            Toggle("Replay with access pending", isOn: $pretendPending)
                .tint(.white.opacity(0.4))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            hairline
            Button {
                HapticManager.medium()
                onboardingDone = false
                dismiss()
            } label: {
                Text("Replay onboarding")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 15)
                    .contentShape(.rect)
            }
            .buttonStyle(.press)
        }
    }

    // MARK: - State

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

    private var notificationsStatus: String {
        if app.notifier.granted {
            return "On"
        }
        return app.notifier.status == .notDetermined ? "Allow" : "Off"
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    private func loadLastNotice() async {
        guard BuildEnvironment.isDev else { return }
        do {
            lastNotice = try await app.database.reader.read { db in
                try db.value(for: .lastNotice).flatMap { try? NoticeTiming.decode($0) }
            }
        } catch {
            Log.ui.error("last notice failed: \(error.localizedDescription)")
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
