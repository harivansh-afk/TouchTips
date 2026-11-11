import BackgroundTasks
import UIKit

/// Exists so capture starts at launch, including background refresh launches.
/// SwiftUI's scene phase arrives too late for that.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let session = AppSession(start: { app in
        #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                return
            }
            NotificationTestFixture.prepare(app)
        #endif
        app.start()
    })

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                session.retry()
                return true
            }
        #endif
        // Registration must finish during launch, even when storage needs a later retry.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: CaptureCoordinator.refreshTaskID, using: .main
        ) { [weak self] task in
            MainActor.assumeIsolated {
                guard let capture = self?.session.app?.capture else {
                    task.setTaskCompleted(success: false)
                    return
                }
                capture.handleRefresh(task)
            }
        }
        session.retry()
        // A device token needs no permission prompt. It's how a client's sign-in reaches this phone for Allow.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        CloudSync.storePushToken(deviceToken)
        Task { await session.app?.cloud.registerDevice() }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Log.notify.error("push registration failed: \(error.localizedDescription, privacy: .public)")
    }

    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        // A background launch before first unlock can also fail to open the database.
        session.retry()
    }
}
