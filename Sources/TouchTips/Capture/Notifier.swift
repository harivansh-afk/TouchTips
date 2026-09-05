import Observation
import TouchTipsCore
import UserNotifications

@MainActor
struct NotificationDelivery {
    var authorization: () async -> UNAuthorizationStatus
    var submittedIDs: () async -> Set<String>
    var submit: (UNNotificationRequest) async throws -> Void

    static var system: Self {
        let center = UNUserNotificationCenter.current()
        return Self(
            authorization: { await center.notificationSettings().authorizationStatus },
            submittedIDs: {
                let delivered = await center.deliveredNotifications().map(\.request.identifier)
                let pending = await center.pendingNotificationRequests().map(\.identifier)
                return Set(delivered + pending)
            },
            submit: { try await center.add($0) }
        )
    }
}

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
    private let delivery: NotificationDelivery
    private var delivering = false
    private var deliveryRequested = false

    private(set) var status: UNAuthorizationStatus = .notDetermined
    /// A person screen a notification asked for. RootView consumes it.
    var pendingPerson: String?

    var granted: Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    init(database: AppDatabase, delivery: NotificationDelivery = .system) {
        self.database = database
        self.delivery = delivery
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
                    UNNotificationAction(
                        identifier: Action.notAMeeting.rawValue,
                        title: "Not a meeting",
                        options: .destructive
                    ),
                ],
                intentIdentifiers: []
            ),
        ])
        Task { await refresh() }
    }

    func refresh() async {
        status = await delivery.authorization()
    }

    func request() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await refresh()
        await deliverPending()
    }

    /// Retry on every wake and after permission is enabled. Stable identifiers reconcile a submission
    /// that succeeded just before the process stopped, before its database acknowledgement.
    func deliverPending(timing: NoticeTiming? = nil) async {
        guard !delivering else {
            deliveryRequested = true
            return
        }
        delivering = true
        defer { delivering = false }
        repeat {
            deliveryRequested = false
            await refresh()
            guard granted else { return }
            do {
                let submitted = await delivery.submittedIDs()
                let notices = try await database.reader.read { db in try PendingNotice.all().fetchAll(db) }
                for notice in notices {
                    try Task.checkCancellation()
                    guard let row = try await database.reader
                        .read({ db in try Person.row(contactID: notice.contactID).fetchOne(db) }) else { continue }
                    if !submitted.contains(Self.identifier(for: notice.contactID)) {
                        try await postMeet(
                            contactID: notice.contactID,
                            name: row.person.name,
                            at: row.meet?.start,
                            placeName: row.place?.name
                        )
                    }
                    var stamps = timing ?? NoticeTiming(
                        heard: notice.createdAt,
                        ticked: notice.createdAt,
                        posted: Date()
                    )
                    stamps.posted = Date()
                    let encoded = try stamps.encoded()
                    try await database.writer.write { db in
                        _ = try PendingNotice.deleteOne(db, key: notice.contactID)
                        try db.setValue(encoded, for: .lastNotice)
                    }
                    Log.notify.notice("notification submitted")
                }
            } catch {
                Log.notify.error("notification remains queued: \(error.localizedDescription)")
                return
            }
        } while deliveryRequested
    }

    private static func identifier(for contactID: String) -> String {
        "\(category)-\(contactID)"
    }

    /// "You just met Alice Chen" over "Blue Bottle @ 2:14 pm".
    private func postMeet(contactID: String, name: String, at date: Date?, placeName: String?) async throws {
        let content = UNMutableNotificationContent()
        content.title = "You just met \(name)"
        content.body = Format.notice(placeName: placeName, at: date)
        content.sound = .default
        content.categoryIdentifier = Self.category
        content.threadIdentifier = Self.category
        content.userInfo = [Self.contactKey: contactID]
        let request = UNNotificationRequest(identifier: Self.identifier(for: contactID), content: content, trigger: nil)
        try await delivery.submit(request)
    }

    func handle(action: String, contactID: String?) {
        guard let contactID, !contactID.isEmpty else { return }
        Log.notify.notice("notification action: \(action, privacy: .public)")
        do {
            switch action {
            case Action.confirm.rawValue: try Ingest.confirmMeet(contactID: contactID, now: .now, to: database)
            case Action.notAMeeting.rawValue: try Ingest.clearMeet(contactID: contactID, to: database)
            case Action.fix.rawValue, UNNotificationDefaultActionIdentifier: pendingPerson = contactID
            default: return
            }
            _ = try database.writer.write { db in try PendingNotice.deleteOne(db, key: contactID) }
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

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let action = response.actionIdentifier
        let contactID = response.notification.request.content.userInfo[Self.contactKey] as? String
        // UIKit's completion updates scene restoration and must run on the main thread. The async
        // delegate's generated completion can run on a pool thread even after MainActor.run returns.
        Task { @MainActor in
            handle(action: action, contactID: contactID)
            completionHandler()
        }
    }
}
