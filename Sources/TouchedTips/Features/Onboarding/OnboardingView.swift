import Contacts
import CoreLocation
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Binding var done: Bool

    /// Flips once the headline has finished typing; everything under it rises in after.
    @State private var revealed = false

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

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            TypewriterText(text: "Who did I meet?\nWhere did I meet them?\nWhen?", font: .display(40)) {
                revealed = true
            }
            .lineSpacing(2)

            Text(
                "TouchedTips lives on your iPhone and logs each new contact as it is created, so you never forget someone again."
            )
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
            .risesIn(revealed, order: 0)

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
            .risesIn(revealed, order: 1)

            PermissionRow(
                title: "Location, Always",
                detail: "So each new contact gets a place.",
                missing: "Places can't be captured.",
                state: locationState,
                openSettings: openSettings
            ) {
                app.capture.requestLocation()
            }
            .risesIn(revealed, order: 2)

            Spacer()
            Button {
                HapticManager.heavy()
                done = true
            } label: {
                Text("Start")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.white)
            .controlSize(.large)
            .risesIn(revealed, order: 3)
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
    /// Hidden until `shown`, then fades up into place. `order` staggers siblings by a beat each.
    func risesIn(_ shown: Bool, order: Int) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .allowsHitTesting(shown)
            .animation(.spring(response: 0.55, dampingFraction: 0.85).delay(Double(order) * 0.09), value: shown)
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
