import UIKit

/// Exists so capture starts at launch, including background relaunches CoreLocation triggers for a visit.
/// SwiftUI's scene phase arrives too late for that.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let app = AppModel()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        app.start()
        return true
    }
}
