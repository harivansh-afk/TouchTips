import CoreLocation

/// One precise fix, or nil after `timeout`. Its own manager, so it never disturbs the presence session.
@MainActor
final class OneShotLocation: NSObject {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func fix(timeout: Duration) async -> CLLocation? {
        guard continuation == nil else { return nil }
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.finish(nil)
        }
        defer { timer.cancel() }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    private func finish(_ location: CLLocation?) {
        guard let continuation else { return }
        self.continuation = nil
        if location == nil { manager.stopUpdatingLocation() }
        continuation.resume(returning: location)
    }
}

extension OneShotLocation: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        MainActor.assumeIsolated { finish(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        MainActor.assumeIsolated { finish(nil) }
    }
}
