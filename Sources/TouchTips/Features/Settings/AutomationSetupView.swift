import AppIntents
import SwiftUI
import TouchTipsCore

/// Shortcuts exposes our action automatically, but only the person can install a personal automation.
struct AutomationSetupView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(CaptureCoordinator.lastShortcutCheckKey) private var lastShortcutCheck = 0.0
    @State private var hasBaseline = false
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        Form {
            Section {
                Text(
                    "When you leave Contacts or Phone, Shortcuts can ask TouchTips to check for new contacts without opening the app."
                )
                Text(
                    "This is not a contact-save trigger. NameDrop and contacts saved elsewhere are discovered at a later check. No background location is used."
                )
                .foregroundStyle(.secondary)
            } header: {
                Text("How it works")
            }

            Section {
                LabeledContent("Contacts", value: app.contactsAccess.granted ? "Full access" : "Full access needed")
                if !app.contactsAccess.granted {
                    Button("Continue with Contacts") {
                        Task {
                            if app.contactsAccess.status == .notDetermined {
                                await app.contactsAccess.request()
                            } else {
                                openSettings()
                            }
                            await refresh()
                        }
                    }
                }
                LabeledContent("Baseline", value: hasBaseline ? "Ready" : "Not ready")
                    .accessibilityIdentifier("automation.baseline")
                Button(busy ? "Checking…" : "Prepare contact baseline") {
                    Task { await prepare() }
                }
                .disabled(busy || !app.contactsAccess.granted)
                .accessibilityIdentifier("automation.prepare")
                if let problem {
                    Text(problem).foregroundStyle(.secondary)
                }
                LabeledContent("Notifications", value: app.notifier.granted ? "Allowed" : "Not allowed")
                if !app.notifier.granted {
                    Button("Continue with Notifications") {
                        Task {
                            if app.notifier.status == .notDetermined {
                                await app.notifier.request()
                            } else {
                                openSettings()
                            }
                        }
                    }
                }
            } header: {
                Text("1. Prepare TouchTips")
            } footer: {
                Text(
                    "The first successful check learns your existing contacts silently. Do this before saving a test contact. Later checks preserve your notes and meeting details. Recording works even without notifications."
                )
            }

            Section {
                Text("In Shortcuts, open Automation and create a new App automation.")
                Text(
                    "Choose Contacts (and Phone if you use it to add people), select Is Closed, and choose Run Immediately or turn off Ask Before Running."
                )
                Text("Add TouchTips’ Check for new contacts action, then save the automation.")
                ShortcutsLink()
                    .disabled(!hasBaseline || !app.contactsAccess.granted)
                    .accessibilityIdentifier("automation.shortcuts")
            } header: {
                Text("2. Connect the trigger")
            } footer: {
                Text(
                    "This button opens TouchTips’ actions in Shortcuts; it cannot install an automation. You must create the App trigger yourself. Setup is specific to this device."
                )
            }

            Section {
                Text(
                    "Save a new test contact in Contacts, then switch to another app. TouchTips should submit a notification if access is allowed. Focus and notification settings may silence it."
                )
                if lastShortcutCheck > 0 {
                    LabeledContent("Last shortcut check") {
                        Text(
                            Date(timeIntervalSince1970: lastShortcutCheck),
                            format: .dateTime.month().day().hour().minute().second()
                        )
                    }
                } else {
                    Text("No successful shortcut check yet.")
                }
            } header: {
                Text("3. Test it")
            } footer: {
                Text(
                    "The timestamp proves the action completed, not that an automation is installed or that a banner appeared. Opening TouchTips also checks contacts, so look for the notification before returning here."
                )
            }
        }
        .navigationTitle("Automatic checks")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await refresh()
        }
    }

    private func refresh() async {
        app.contactsAccess.refresh()
        await app.notifier.refresh()
        do {
            hasBaseline = try await app.database.reader.read { db in
                try db.value(for: .contactsHistoryToken) != nil
            }
        } catch {
            hasBaseline = false
            problem = "Saved data is unavailable. Try again after unlocking your iPhone."
        }
    }

    private func prepare() async {
        busy = true
        problem = nil
        defer { busy = false }
        let success = await app.capture.tick(.user)
        await refresh()
        if !success || !hasBaseline {
            problem = "The baseline could not be prepared. Check full Contacts access and try again."
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}
