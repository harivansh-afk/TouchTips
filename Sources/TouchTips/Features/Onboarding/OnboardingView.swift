import Contacts
import CoreLocation
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Binding var done: Bool

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
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text("Where did\nyou meet\neveryone?")
                .font(.display(52))
                .lineSpacing(-2)
            Text("touchtips watches new contacts and your visits, and remembers when and where each person came in. Nothing leaves this phone.")
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            PermissionRow(
                title: "Contacts",
                detail: "Full access, so new people can be noticed.",
                missing: "New people won't be noticed.",
                state: contactsState,
                openSettings: openSettings
            ) {
                Task {
                    await app.contactsAccess.request()
                    app.capture.scheduleTick()
                }
            }
            PermissionRow(
                title: "Location, Always",
                detail: "Visits wake the app and give the place. iOS asks for Always later, after the app has used your location once.",
                missing: "Places can't be captured.",
                state: locationState,
                openSettings: openSettings
            ) {
                app.capture.requestLocation()
            }

            Spacer()
            Button {
                HapticManager.heavy()
                done = true
            } label: {
                Text("Start").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.white)
            .controlSize(.large)
        }
        .padding(26)
        .background(Color.black)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { app.contactsAccess.refresh() }
        }
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
                if state == .denied { openSettings() } else { action() }
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
