import CoreLocation
import Observation

/// While-in-use location and nothing more. There is no location background mode: a fix is only
/// ever taken while the app is open, for a place the user is about to see.
@MainActor
@Observable
final class LocationAccess: NSObject {
    /// A fix older or vaguer than this cannot tell one café from the next.
    static let maxAge: TimeInterval = 60
    static let maxUncertainty: CLLocationAccuracy = 100

    private let manager = CLLocationManager()
    private var answer: CheckedContinuation<Void, Never>?
    private var waiting: [UUID: CheckedContinuation<CLLocation?, Never>] = [:]

    private(set) var status: CLAuthorizationStatus
    /// Approximate location is a few kilometres wide: no use for naming a place.
    private(set) var precise: Bool

    override init() {
        status = manager.authorizationStatus
        precise = manager.accuracyAuthorization == .fullAccuracy
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    var allowed: Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    /// Allowed, and precise enough to name the place.
    var usable: Bool {
        allowed && precise
    }

    /// Ask once. Returns when the user has answered, or at once if they already have.
    func request() async {
        guard status == .notDetermined, answer == nil else { return }
        await withCheckedContinuation { continuation in
            answer = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Where the phone is, to within `maxUncertainty`, or nil within `timeout`.
    func fix(timeout: Duration = .seconds(6)) async -> CLLocation? {
        guard usable, !Task.isCancelled else { return nil }
        if let recent = manager.location, Self.good(recent) {
            return recent
        }
        let id = UUID()
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.waiting.removeValue(forKey: id)?.resume(returning: nil)
        }
        defer { timer.cancel() }
        let location = await withCheckedContinuation { continuation in
            waiting[id] = continuation
            if waiting.count == 1 {
                manager.requestLocation()
            }
        }
        guard let location else {
            Log.geocode.notice("no fix")
            return nil
        }
        guard Self.good(location) else {
            Log.geocode.notice(
                "fix too vague or old: \(Int(location.horizontalAccuracy), privacy: .public) m, \(Int(-location.timestamp.timeIntervalSinceNow), privacy: .public) s"
            )
            return nil
        }
        return location
    }

    private static func good(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= maxUncertainty
            && -location.timestamp.timeIntervalSinceNow <= maxAge
    }

    private func finish(_ location: CLLocation?) {
        let continuations = waiting.values
        waiting.removeAll()
        for continuation in continuations {
            continuation.resume(returning: location)
        }
    }
}

extension LocationAccess: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let precise = manager.accuracyAuthorization == .fullAccuracy
        MainActor.assumeIsolated {
            self.status = status
            self.precise = precise
            // The callback also fires when the delegate is set, before anyone has answered.
            if status != .notDetermined {
                answer?.resume()
                answer = nil
            }
            if !usable {
                finish(nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        MainActor.assumeIsolated { finish(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Log.geocode.notice("location failed: \(error.localizedDescription, privacy: .public)")
        MainActor.assumeIsolated { finish(nil) }
    }
}
