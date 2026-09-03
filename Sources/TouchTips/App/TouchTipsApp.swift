import SwiftUI

@main
struct TouchTipsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(delegate.app)
                .preferredColorScheme(.dark)
        }
    }
}
