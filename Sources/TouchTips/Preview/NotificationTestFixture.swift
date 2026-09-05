#if DEBUG && targetEnvironment(simulator)
    import Contacts
    import Foundation
    import TouchTipsCore
    import UserNotifications

    /// Simulator UI tests only. Delivery and response handling still use the real notification center.
    enum NotificationTestFixture {
        static var session: String? {
            // A regular-use test must not inherit a previous notification test's startup state.
            if ProcessInfo.processInfo.environment["TOUCHTIPS_QA_SESSION"] != nil { return nil }
            if let session = ProcessInfo.processInfo.environment["TOUCHTIPS_UI_TEST_SESSION"] {
                UserDefaults.standard.set(session, forKey: "notificationTestSession")
                return session
            }
            return UserDefaults.standard.string(forKey: "notificationTestSession")
        }

        @MainActor
        static func prepare(_ app: AppModel) {
            guard session != nil else { return }
            UserDefaults.standard.set(true, forKey: "onboardingDone")
            let environment = ProcessInfo.processInfo.environment
            do {
                if let id = environment["TOUCHTIPS_TEST_PERSON"] {
                    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                    // Establish the test database's history cursor before adding a UI-only person.
                    if let token = CNContactStore().currentHistoryToken {
                        try Ingest.apply(ContactChangeSet(token: token), now: .now, to: app.database)
                    }
                    try Ingest.addExact(
                        contactID: id,
                        name: "Notification Test Person",
                        at: .now,
                        placeID: nil,
                        to: app.database
                    )
                }
                if let id = environment["TOUCHTIPS_DELETE_PERSON"] {
                    _ = try app.database.writer.write { db in try Person.deleteOne(db, key: id) }
                }
            } catch {
                preconditionFailure("Notification fixture failed: \(error)")
            }
            Task { await app.notifier.request() }
        }
    }
#endif
