import UIKit

/// End the system assertion immediately on expiration, even if Contacts is still returning from I/O.
@MainActor
final class CaptureBackgroundTask {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(expiration: @escaping @MainActor () -> Void) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Capture contacts") { [weak self] in
            // UIApplication documents this callback on the main thread.
            MainActor.assumeIsolated {
                expiration()
                self?.end()
            }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
