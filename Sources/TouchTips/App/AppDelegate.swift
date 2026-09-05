import BackgroundTasks
import UIKit

/// Exists so capture starts at launch, including background relaunches CoreLocation triggers for a visit.
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
        return true
    }
}
