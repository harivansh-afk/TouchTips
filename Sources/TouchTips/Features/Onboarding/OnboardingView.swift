import Contacts
import CoreLocation
import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    /// Called once the screen has finished leaving; the caller swaps in the app.
    let finish: () -> Void

    /// Flips once the headline has finished typing; everything under it rises in after.
    @State private var revealed = false
    /// Flips on Start; everything falls away, then `finish` runs.
    @State private var leaving = false

    private var contactsState: PermissionState {
        switch app.contactsAccess.status {
        case .authorized: .granted
        case .denied, .restricted, .limited: .denied
        default: .pending
        }
    }

    private var locationState: PermissionState {
        switch app.capture.locationPermissionAction {
        case .allowed: .granted
        case .openSettings: .denied
        case .request: .pending
        }
    }

    private var notificationsState: PermissionState {
        switch app.notifier.status {
        case .authorized, .provisional, .ephemeral: .granted
        case .denied: .denied
        default: .pending
        }
    }

    /// Everything under the headline falls away, the headline sweeps out on its heels, and the
    /// overlay starts fading while the last glyphs are still going, so there is no empty frame.
    private func leave() {
        leaving = true
        Task {
            try? await Task.sleep(for: .milliseconds(280))
            finish()
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            TypewriterText(
                text: "Who did I meet?\nWhere did I meet them?\nWhen?",
                font: .display(40),
                leaving: leaving
            ) {
                revealed = true
            }
            .lineSpacing(2)

            Text(
                "TouchTips lives on your iPhone and remembers new contacts and where you may have met. Background discovery can be delayed; opening the app checks for new people."
            )
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
            .staged(revealed, leaving: leaving, order: 0)

            PermissionRow(
                title: "Contacts",
                missing: "New people won't be noticed.",
                state: contactsState,
                openSettings: openSettings
            ) {
                Task {
                    await app.contactsAccess.request()
                    app.capture.scheduleTick(.user)
                }
            }
            .staged(revealed, leaving: leaving, order: 1)

            PermissionRow(
                title: "Location, Always",
                missing: app.capture.locationStatus == .authorizedWhenInUse
                    ? LocationPermissionAction.backgroundExplanation : "Venues can't be captured.",
                state: locationState,
                openSettings: openSettings
            ) {
                app.capture.requestLocation()
            }
            .staged(revealed, leaving: leaving, order: 2)

            PermissionRow(
                title: "Notifications",
                missing: "You won't hear who you met.",
                state: notificationsState,
                openSettings: openSettings
            ) {
                Task { await app.notifier.request() }
            }
            .staged(revealed, leaving: leaving, order: 3)

            Spacer()
            Button {
                HapticManager.heavy()
                leave()
            } label: {
                Text("Start")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.white)
            .controlSize(.large)
            .staged(revealed, leaving: leaving, order: 4)
        }
        .padding(26)
        // Edge to edge: this is an overlay on the finished app, nothing may show around it.
        .background { Color.ground.ignoresSafeArea() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                app.contactsAccess.refresh()
                Task { await app.notifier.refresh() }
            }
        }
    }
}

private extension View {
    /// Hidden until `shown`, then fades up into place, `order` beats after its siblings. On
    /// `leaving` everything falls away together; the headline's sweep carries the sequence.
    func staged(_ shown: Bool, leaving: Bool, order: Int) -> some View {
        let visible = shown && !leaving
        return opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 14)
            .allowsHitTesting(visible)
            .animation(
                leaving ? .easeIn(duration: 0.28) : .spring(response: 0.55, dampingFraction: 0.85)
                    .delay(Double(order) * 0.09),
                value: visible
            )
    }
}

private enum PermissionState {
    case pending, granted, denied
}

private struct PermissionRow: View {
    let title: String
    /// What the app loses without it. Shown only once the answer was no.
    let missing: String
    let state: PermissionState
    let openSettings: () -> Void
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if state == .denied {
                    Text(missing).font(.footnote).foregroundStyle(.primary)
                }
            }
            Spacer(minLength: 8)
            Button(verb) {
                HapticManager.heavy()
                if state == .denied {
                    openSettings()
                } else {
                    action()
                }
            }
            .buttonStyle(.glass)
            .disabled(state == .granted)
        }
        .padding(16)
        .glassEffect(.clear, in: .rect(cornerRadius: 20))
    }

    private var verb: String {
        switch state {
        case .pending: "Allow"
        case .granted: "Allowed"
        case .denied: "Open Settings"
        }
    }
}
