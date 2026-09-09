import UIKit

/// End the system assertion immediately on expiration, even if Contacts is still returning from I/O.
@MainActor
final class CaptureBackgroundTask {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private let finish: (UIBackgroundTaskIdentifier) -> Void

    init(
        expiration: @escaping @MainActor () -> Void,
        begin: (@escaping @MainActor () -> Void) -> UIBackgroundTaskIdentifier = {
            UIApplication.shared.beginBackgroundTask(withName: "Capture contacts", expirationHandler: $0)
        },
        end: @escaping (UIBackgroundTaskIdentifier) -> Void = { UIApplication.shared.endBackgroundTask($0) }
    ) {
        finish = end
        identifier = begin { [weak self] in
            // UIApplication documents this callback on the main thread.
            MainActor.assumeIsolated {
                expiration()
                self?.end()
            }
        }
    }

    isolated deinit {
        end()
    }

    func end() {
        guard identifier != .invalid else { return }
        let ended = identifier
        identifier = .invalid
        finish(ended)
    }
}
