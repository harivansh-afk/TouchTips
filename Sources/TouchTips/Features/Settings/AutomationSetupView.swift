import SwiftUI
import TouchTipsCore

/// The one-time setup for automatic checks. iOS lets only the person create the Shortcuts
/// automation, so this screen gets everything else ready, opens Shortcuts at the right page,
/// and shows the five taps left. Modelled on the setup flows of one sec and Opal.
struct AutomationSetupView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(CaptureCoordinator.lastShortcutCheckKey) private var lastShortcutCheck = 0.0
    @State private var hasBaseline = false
    @State private var preparing = false

    private var ready: Bool {
        app.contactsAccess.granted && hasBaseline
    }

    private var checked: Date? {
        lastShortcutCheck > 0 ? Date(timeIntervalSince1970: lastShortcutCheck) : nil
    }

    var body: some View {
        Form {
            Section {
                Text(
                    "Add someone in Contacts, leave Contacts, and TouchTips reminds you to note where you met. No background location."
                )
                .foregroundStyle(.secondary)
            }

            Section("1. Allow") {
                accessRow("Contacts", ok: app.contactsAccess.granted, okText: "Full access") {
                    Task {
                        if app.contactsAccess.status == .notDetermined {
                            await app.contactsAccess.request()
                        } else {
                            openSettings()
                        }
                        await refresh()
                    }
                }
                accessRow("Notifications", ok: app.notifier.granted, okText: "Allowed") {
                    Task {
                        if app.notifier.status == .notDetermined {
                            await app.notifier.request()
                        } else {
                            openSettings()
                        }
                    }
                }
            }

            Section {
                Button {
                    openShortcuts()
                } label: {
                    Label(
                        preparing ? "Reading your contacts…" : "Open Shortcuts",
                        systemImage: "arrow.up.forward.app"
                    )
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(!ready)
                .accessibilityIdentifier("automation.shortcuts")
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                step(1, "Tap **App**.")
                step(2, "Tap **Choose**, pick **Contacts**, then the tick.")
                step(3, "Select **Is Closed**.")
                step(4, "Select **Run Immediately**.", warning: "Otherwise iOS asks before every check.")
                step(5, "Tap **Next**, then **Check for new contacts**.")

                Image("shortcut-step-trigger")
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 12))
                    .frame(maxWidth: 280)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Shortcuts trigger set to Contacts, Is Closed, Run Immediately")
                    .listRowBackground(Color.clear)
            } header: {
                Text("2. Add the automation")
            } footer: {
                Text(
                    "Steps 1 to 4 should look like the picture. Shortcuts saves the automation when you tap the action."
                )
            }

            Section("3. Test it") {
                if let checked {
                    Label {
                        Text("Working. Last check \(checked, format: .dateTime.month().day().hour().minute()).")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                } else {
                    Text(
                        "Save a test contact in Contacts, then go Home. A TouchTips notification should arrive within a few seconds. Until then, opening TouchTips catches up on its own."
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Automatic checks")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await refresh()
        }
    }

    private func accessRow(_ title: String, ok: Bool, okText: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if ok {
                Text(okText).foregroundStyle(.secondary)
            } else {
                Button("Allow", action: action)
            }
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey, warning: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                if let warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    /// Straight to the trigger picker. The URL is undocumented, so fall back to the app itself.
    private func openShortcuts() {
        HapticManager.medium()
        openURL(URL(string: "shortcuts://create-automation")!) { accepted in
            if !accepted, let fallback = URL(string: "shortcuts://") {
                openURL(fallback)
            }
        }
    }

    /// The silent baseline of existing contacts, taken here so a test contact is never swallowed.
    private func refresh() async {
        app.contactsAccess.refresh()
        await app.notifier.refresh()
        hasBaseline = await (try? app.database.reader.read { db in
            try db.value(for: .contactsHistoryToken) != nil
        }) ?? false
        if !hasBaseline, app.contactsAccess.granted, !preparing {
            preparing = true
            _ = await app.capture.tick(.user)
            preparing = false
            hasBaseline = await (try? app.database.reader.read { db in
                try db.value(for: .contactsHistoryToken) != nil
            }) ?? false
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}
