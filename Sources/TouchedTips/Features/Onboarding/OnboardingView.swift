import Contacts
import CoreLocation
import SwiftUI

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
        switch app.capture.locationStatus {
        case .authorizedAlways: .granted
        case .denied, .restricted: .denied
        default: .pending
        }
    }

    /// Bottom up, the way it came in: Start, the rows, the body, then the headline sweeps out. The
    /// app starts coming in while the last glyphs are still going, so there is no empty frame.
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
                "TouchedTips lives on your iPhone and logs each new contact as it is created, so you never forget someone again."
            )
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
            .staged(revealed, leaving: leaving, order: 0)

            PermissionRow(
                title: "Contacts",
                detail: "So new people get noticed.",
                missing: "New people won't be noticed.",
                state: contactsState,
                openSettings: openSettings
            ) {
                Task {
                    await app.contactsAccess.request()
                    app.capture.scheduleTick()
                }
            }
            .staged(revealed, leaving: leaving, order: 1)

            PermissionRow(
                title: "Location, Always",
                detail: "So each new contact gets a place.",
                missing: "Places can't be captured.",
                state: locationState,
                openSettings: openSettings
            ) {
                app.capture.requestLocation()
            }
            .staged(revealed, leaving: leaving, order: 2)

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
            .staged(revealed, leaving: leaving, order: 3)
        }
        .padding(26)
        .background(Color.ground)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                app.contactsAccess.refresh()
            }
        }
    }
}

private extension View {
    /// Hidden until `shown`, then fades up into place; on `leaving` it falls back out. Siblings are
    /// staggered by `order`, first in and last out.
    func staged(_ shown: Bool, leaving: Bool, order: Int) -> some View {
        let visible = shown && !leaving
        let delay = leaving ? Double(3 - order) * 0.03 : Double(order) * 0.09
        return opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 14)
            .allowsHitTesting(visible)
            .animation(
                leaving ? .easeIn(duration: 0.28).delay(delay) : .spring(response: 0.55, dampingFraction: 0.85)
                    .delay(delay),
                value: visible
            )
    }
}

private enum PermissionState {
    case pending, granted, denied
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    /// What the app loses without it. Shown only once the answer was no.
    let missing: String
    let state: PermissionState
    let openSettings: () -> Void
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
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
