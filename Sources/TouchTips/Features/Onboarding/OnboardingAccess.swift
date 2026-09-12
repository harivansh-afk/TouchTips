import Contacts
import SwiftUI
import UserNotifications

/// The three things the first-run screen asks for, in the order it asks.
enum Permission: CaseIterable, Identifiable {
    case contacts, location, notifications

    var id: Self { self }

    var title: String {
        switch self {
        case .contacts: "Contacts"
        case .location: "Location, Always"
        case .notifications: "Notifications"
        }
    }
}

enum PermissionState {
    case pending, granted, denied
}

/// Reads each answer from the app and knows the one way to ask for it. With `pretend` on, a dev
/// switch for replaying the screen on a phone that has already answered, every answer starts out
/// pending and Allow grants after a beat, so the whole choreography can be watched again.
@MainActor
struct OnboardingAccess {
    let app: AppModel
    var pretend = false
    @Binding var pretendGranted: Set<Permission>

    init(app: AppModel, pretend: Bool, pretendGranted: Binding<Set<Permission>>) {
        self.app = app
        self.pretend = pretend || Self.autoplay
        _pretendGranted = pretendGranted
    }

    static let pretendKey = "onboardingPretendPending"

    func state(_ permission: Permission) -> PermissionState {
        if pretend {
            return pretendGranted.contains(permission) ? .granted : .pending
        }
        switch permission {
        case .contacts:
            return switch app.contactsAccess.status {
            case .authorized: .granted
            case .denied, .restricted, .limited: .denied
            default: .pending
            }
        case .location:
            return switch app.capture.locationPermissionAction {
            case .allowed: .granted
            case .openSettings: .denied
            case .request: .pending
            }
        case .notifications:
            return switch app.notifier.status {
            case .authorized, .provisional, .ephemeral: .granted
            case .denied: .denied
            default: .pending
            }
        }
    }

    var allGranted: Bool {
        Permission.allCases.allSatisfy { state($0) == .granted }
    }

    /// Simulator only: the screen answers itself, one permission a beat, then continues. So the
    /// whole choreography can be recorded without a finger. Forces `pretend` on.
    static let autoplay: Bool = {
        #if DEBUG && targetEnvironment(simulator)
            return ProcessInfo.processInfo.environment["TOUCHTIPS_ONBOARDING_AUTOPLAY"] == "1"
        #else
            return false
        #endif
    }()

    /// The line under a refused row, only where there is something to say: When In Use is not enough.
    func note(_ permission: Permission) -> String? {
        guard !pretend, permission == .location, app.capture.locationStatus == .authorizedWhenInUse else {
            return nil
        }
        return LocationPermissionAction.backgroundExplanation
    }

    func request(_ permission: Permission) {
        if pretend {
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                pretendGranted.insert(permission)
            }
            return
        }
        switch permission {
        case .contacts:
            Task {
                await app.contactsAccess.request()
                app.capture.scheduleTick(.user)
            }
        case .location:
            app.capture.requestLocation()
        case .notifications:
            Task { await app.notifier.request() }
        }
    }

    /// Called when the scene comes back, after a system prompt has been answered.
    func refresh() {
        app.contactsAccess.refresh()
        Task { await app.notifier.refresh() }
    }
}

extension View {
    /// The system's Settings page for this app, where a refused permission is changed.
    func openAppSettings(_ openURL: OpenURLAction) {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

/// One permission as a glass row: its name, a note once it was refused, and the one verb.
struct PermissionRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL

    let permission: Permission
    let access: OnboardingAccess

    private var state: PermissionState { access.state(permission) }

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(spacing: 14))
    }

    var body: some View {
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title).font(.headline)
                if state == .denied, let note = access.note(permission) {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }
            Button(state == .granted ? "Allowed" : "Continue") {
                HapticManager.heavy()
                if state == .denied {
                    openAppSettings(openURL)
                } else {
                    access.request(permission)
                }
            }
            .buttonStyle(.glass)
            .fixedSize(horizontal: false, vertical: true)
            .disabled(state == .granted)
            .animation(.snappy, value: state)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.clear, in: .rect(cornerRadius: 20))
    }
}
