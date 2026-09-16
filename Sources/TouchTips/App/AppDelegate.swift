import BackgroundTasks
import UIKit

/// Registers system callbacks at launch. Intent and UI entry points share the same runtime.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let session = AppRuntime.session

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
        return true
    }

    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        // A background launch before first unlock can also fail to open the database.
        session.retry()
        session.app?.capture.restoreFence()
    }
}
