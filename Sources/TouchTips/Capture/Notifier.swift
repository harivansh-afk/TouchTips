import Observation
import TouchTipsCore
import UserNotifications

@MainActor
struct NotificationDelivery {
    var authorization: () async -> UNAuthorizationStatus
    var submittedIDs: () async -> Set<String>
    var submit: (UNNotificationRequest) async throws -> Void
    var remove: ([String]) -> Void = { _ in }

    static var system: Self {
        let center = UNUserNotificationCenter.current()
        return Self(
            authorization: {
                let settings = await center.notificationSettings()
                Log.notify.notice(
                    "presentation settings: alerts=\(settings.alertSetting.rawValue, privacy: .public) sound=\(settings.soundSetting.rawValue, privacy: .public) lockScreen=\(settings.lockScreenSetting.rawValue, privacy: .public) center=\(settings.notificationCenterSetting.rawValue, privacy: .public) summary=\(settings.scheduledDeliverySetting.rawValue, privacy: .public)"
                )
                return settings.authorizationStatus
            },
            submittedIDs: {
                let delivered = await center.deliveredNotifications().map(\.request.identifier)
                let pending = await center.pendingNotificationRequests().map(\.identifier)
                return Set(delivered + pending)
            },
            submit: { try await center.add($0) },
            remove: {
                center.removePendingNotificationRequests(withIdentifiers: $0)
                center.removeDeliveredNotifications(withIdentifiers: $0)
            }
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
    private let retryDelays: [Duration]
    private var deliveryTask: Task<Void, Never>?
    private var deliveryRequested = false

    private(set) var status: UNAuthorizationStatus = .notDetermined
    /// A person screen a notification asked for. RootView consumes it.
    var pendingPerson: String?

    var granted: Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    init(
        database: AppDatabase, delivery: NotificationDelivery = .system,
        retryDelays: [Duration] = [.seconds(2), .seconds(5)]
    ) {
        self.database = database
        self.delivery = delivery
        self.retryDelays = retryDelays
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
        Log.notify.notice("notification authorization: \(self.status.rawValue, privacy: .public)")
    }

    func request() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await refresh()
        await deliverPending()
    }

    /// Retry on every wake and after permission is enabled. Stable identifiers reconcile a submission
    /// that succeeded just before the process stopped, before its database acknowledgement.
    func deliverPending(timing: NoticeTiming? = nil) async {
        guard !Task.isCancelled else { return }
        let work: Task<Void, Never>
        if let deliveryTask {
            deliveryRequested = true
            work = deliveryTask
        } else {
            work = Task { [weak self] in
                guard let self else { return }
                defer { deliveryTask = nil }
                var retries = retryDelays.makeIterator()
                repeat {
                    deliveryRequested = false
                    let failed = await submitQueued(timing: timing)
                    guard !Task.isCancelled else { return }
                    if deliveryRequested {
                        continue
                    }
                    guard failed, let delay = retries.next() else { return }
                    do {
                        try await Task.sleep(for: delay)
                    } catch { return }
                    deliveryRequested = true
                } while deliveryRequested
            }
            deliveryTask = work
        }
        // Every caller holds its background window until the shared delivery actually finishes.
        await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        if work.isCancelled, !Task.isCancelled {
            await deliverPending(timing: timing)
        }
    }

    func cancelDelivery() async {
        deliveryTask?.cancel()
        await deliveryTask?.value
    }

    private func submitQueued(timing: NoticeTiming?) async -> Bool {
        await refresh()
        guard granted, !Task.isCancelled else { return false }
        do {
            var submitted = await delivery.submittedIDs()
            let notices = try await database.reader.read { db in try PendingNotice.all().fetchAll(db) }
            var failed = false
            Log.notify.notice("notification queue: \(notices.count, privacy: .public)")
            for notice in notices {
                do {
                    try Task.checkCancellation()
                    // An earlier submission can suspend while this person is forgotten or reset.
                    guard let row = try await database.reader.read({ db -> PersonRow? in
                        guard try PendingNotice.fetchOne(db, key: notice.contactID) == notice else { return nil }
                        return try Person.row(contactID: notice.contactID).fetchOne(db)
                    }) else { continue }
                    try Task.checkCancellation()
                    let identifier = Self.identifier(for: notice.contactID)
                    if !submitted.contains(identifier) {
                        try await postMeet(
                            contactID: notice.contactID,
                            name: row.person.name,
                            meet: row.meet,
                            placeName: row.place?.name
                        )
                        // Keep this receipt even if SQLite acknowledgement fails on this pass.
                        submitted.insert(identifier)
                    }
                    // A current scan's timing must not conceal how long an older notice waited.
                    var stamps = timing.flatMap {
                        notice.createdAt >= $0.ticked.addingTimeInterval(-0.001) ? $0 : nil
                    } ?? NoticeTiming(
                        heard: notice.createdAt,
                        ticked: notice.createdAt,
                        posted: Date()
                    )
                    stamps.posted = Date()
                    let encoded = try stamps.encoded()
                    let acknowledged = try await database.writer.write { db in
                        guard try PendingNotice.fetchOne(db, key: notice.contactID) == notice else { return false }
                        _ = try PendingNotice.deleteOne(db, key: notice.contactID)
                        try db.setValue(encoded, for: .lastNotice)
                        return true
                    }
                    if acknowledged {
                        Log.notify.notice("notification submitted; queue age \(stamps.total, privacy: .public) s")
                    } else {
                        delivery.remove([identifier])
                    }
                } catch is CancellationError {
                    return false
                } catch {
                    // A failing record cannot starve unrelated people behind it.
                    failed = true
                    Log.notify.error("notification remains queued: \(error.localizedDescription)")
                }
            }
            return failed
        } catch {
            Log.notify.error("notification queue unavailable: \(error.localizedDescription)")
            return true
        }
    }

    private static func identifier(for contactID: String) -> String {
        "\(category)-\(contactID)"
    }

    /// Discovery is reported as a new contact; only user-confirmed records claim a meeting.
    private func postMeet(contactID: String, name: String, meet: Meet?, placeName: String?) async throws {
        let content = UNMutableNotificationContent()
        content.title = meet?.isConfirmed == true ? "Meeting recorded: \(name)" : "New contact: \(name)"
        content.body = meet?.isConfirmed == true
            ? [placeName, meet.map(Format.dateLine)].compactMap(\.self).joined(separator: " · ")
            : "Review the suggested meeting details in TouchTips."
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
