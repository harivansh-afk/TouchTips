import Observation
import TouchTipsCore
import UserNotifications

/// Local notifications only: one per new person, with the answer and a way to fix it.
@MainActor
@Observable
final class Notifier: NSObject {
    private enum Action: String {
        case confirm, fix, notAMeeting
    }

    private nonisolated static let category = "meet"
    private nonisolated static let contactKey = "contactID"

    private let database: AppDatabase
    private let center = UNUserNotificationCenter.current()

    private(set) var status: UNAuthorizationStatus = .notDetermined
    /// A person screen a notification asked for. RootView consumes it.
    var pendingPerson: String?

    var granted: Bool { status == .authorized || status == .provisional || status == .ephemeral }

    init(database: AppDatabase) {
        self.database = database
        super.init()
    }

    /// Call before `didFinishLaunching` returns, so a tap that launched the app is delivered.
    func activate() {
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.category,
                actions: [
                    UNNotificationAction(identifier: Action.confirm.rawValue, title: "That's right"),
                    UNNotificationAction(identifier: Action.fix.rawValue, title: "Fix", options: .foreground),
                    UNNotificationAction(identifier: Action.notAMeeting.rawValue, title: "Not a meeting", options: .destructive),
                ],
                intentIdentifiers: []
            ),
        ])
        Task { await refresh() }
    }

    func refresh() async {
        status = await center.notificationSettings().authorizationStatus
    }

    func request() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await refresh()
    }

    /// "You just met Alice Chen" over "Blue Bottle @ 2:14 pm".
    func postMeet(contactID: String, name: String, at date: Date?, placeName: String?) async {
        let content = UNMutableNotificationContent()
        content.title = "You just met \(name)"
        content.body = Format.notice(placeName: placeName, at: date)
        content.sound = .default
        content.categoryIdentifier = Self.category
        content.threadIdentifier = Self.category
        content.userInfo = [Self.contactKey: contactID]
        let request = UNNotificationRequest(identifier: "\(Self.category)-\(contactID)", content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            Log.notify.error("not posted: \(error.localizedDescription)")
        }
    }

    private func handle(action: String, contactID: String?) {
        guard let contactID else { return }
        do {
            switch Action(rawValue: action) {
            case .confirm: try Ingest.confirmMeet(contactID: contactID, now: .now, to: database)
            case .notAMeeting: try Ingest.clearMeet(contactID: contactID, to: database)
            case .fix, nil: pendingPerson = contactID
            }
        } catch {
            Log.notify.error("action \(action) failed: \(error.localizedDescription)")
        }
    }
}

extension Notifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let contactID = response.notification.request.content.userInfo[Self.contactKey] as? String
        await MainActor.run { handle(action: action, contactID: contactID) }
    }
}
