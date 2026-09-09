import CoreLocation

/// The asynchronous Core Location boundary. Tests can suspend a read/write without opening a second named monitor.
@MainActor
struct CaptureFenceMonitor {
    var center: () async -> CLLocation?
    var replace: (CLLocation) async -> Void
    var remove: () async -> Void
    var observe: (@escaping @MainActor () -> Void) async throws -> Void

    static func system() async -> Self {
        // Both identifiers are persisted by Core Location; keep them across app upgrades.
        let monitor = await CLMonitor("TouchedTipsFence")
        let identifier = "breadcrumb"
        return Self(
            center: {
                guard let record = await monitor.record(for: identifier),
                      let condition = record.condition as? CLMonitor.CircularGeographicCondition else { return nil }
                return CLLocation(latitude: condition.center.latitude, longitude: condition.center.longitude)
            },
            replace: { location in
                // add replaces the existing identifier. Removing first leaves a gap and discards its state.
                await monitor.add(
                    CLMonitor.CircularGeographicCondition(center: location.coordinate, radius: CaptureFence.radius),
                    identifier: identifier, assuming: .satisfied
                )
            },
            remove: { await monitor.remove(identifier) },
            observe: { wake in
                for try await event in await monitor.events {
                    try Task.checkCancellation()
                    guard event.identifier == identifier else { continue }
                    Log.capture.notice(
                        "fence event: state=\(event.state.rawValue, privacy: .public) insufficientlyInUse=\(event.insufficientlyInUse, privacy: .public) sessionRequired=\(event.serviceSessionRequired, privacy: .public) accuracyLimited=\(event.accuracyLimited, privacy: .public) persistenceUnavailable=\(event.persistenceUnavailable, privacy: .public)"
                    )
                    if event.state == .satisfied || event.state == .unsatisfied {
                        wake()
                    }
                }
            }
        )
    }
}

/// Owns one named monitor and its Always authorization session for the lifetime of automatic location capture.
/// It consumes system location events; it does not poll location or keep the process continuously awake.
@MainActor
final class CaptureFence {
    static let radius: CLLocationDistance = 150
    private let beginSession: @MainActor () -> @MainActor () -> Void
    private let connect: () async -> CaptureFenceMonitor
    private let wake: () -> Void
    private var endSession: (@MainActor () -> Void)?
    private var monitor: CaptureFenceMonitor?
    private var opening: Task<CaptureFenceMonitor, Never>?
    private var observation: Task<Void, Never>?
    private var mutation: Task<Void, Never>?
    private var authorized = false
    private var protectedDataAvailable = false
    private var desiredLocation: CLLocation?
    private var needsRemoval = false
    private var revision = 0

    init(
        beginSession: @escaping @MainActor () -> @MainActor () -> Void = CaptureFence.alwaysSession,
        connect: @escaping () async -> CaptureFenceMonitor = CaptureFenceMonitor.system,
        wake: @escaping () -> Void
    ) {
        self.beginSession = beginSession
        self.connect = connect
        self.wake = wake
    }

    isolated deinit {
        observation?.cancel()
        endSession?()
    }

    func configure(authorized: Bool, protectedDataAvailable: Bool) {
        self.authorized = authorized
        self.protectedDataAvailable = protectedDataAvailable
        if authorized {
            // Synchronous: retake authorization during launch, before awaiting the monitor or its events.
            if endSession == nil {
                endSession = beginSession()
            }
        } else {
            endSession?()
            endSession = nil
        }
        guard authorized, protectedDataAvailable else {
            observation?.cancel()
            return
        }
        startObserving()
        if desiredLocation != nil || needsRemoval {
            synchronize()
        }
    }

    /// Reuse a persisted fence until a fresh, accurate fix has moved far enough to justify replacing it.
    func update(_ location: CLLocation, now: Date = .now) {
        guard authorized, CLLocationCoordinate2DIsValid(location.coordinate),
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= Self.radius,
              abs(location.timestamp.timeIntervalSince(now)) <= 120 else { return }
        if let desiredLocation, location.timestamp < desiredLocation.timestamp {
            return
        }
        desiredLocation = location
        revision += 1
        synchronize()
    }

    /// Joins any in-flight add, then removes it. Reset cannot return while an old add can recreate the fence.
    func reset() async {
        desiredLocation = nil
        needsRemoval = true
        revision += 1
        await synchronize()?.value
    }

    private func connection() async -> CaptureFenceMonitor? {
        guard protectedDataAvailable else { return nil }
        if let monitor {
            return monitor
        }
        if let opening {
            return await opening.value
        }
        guard authorized, protectedDataAvailable else { return nil }
        let connect = connect
        let task = Task { await connect() }
        opening = task
        let result = await task.value
        monitor = result
        opening = nil
        return result
    }

    private func startObserving() {
        guard observation == nil else { return }
        observation = Task { [weak self] in
            defer {
                self?.observation = nil
                // Permission can be restored before a cancelled iterator has unwound.
                if Task.isCancelled, self?.authorized == true, self?.protectedDataAvailable == true {
                    self?.startObserving()
                }
            }
            guard let monitor = await self?.connection(), self?.authorized == true,
                  self?.protectedDataAvailable == true,
                  !Task.isCancelled else { return }
            do {
                try await monitor.observe { [weak self] in
                    guard let self, authorized, protectedDataAvailable else { return }
                    wake()
                }
            } catch is CancellationError {
                // Permission loss ends observation; the next eligible configure resumes the same monitor.
            } catch {
                Log.capture.error("fence observation ended: \(error.localizedDescription)")
            }
            // A later foreground/location/refresh wake retries a failed stream, without a polling loop.
        }
    }

    @discardableResult
    private func synchronize() -> Task<Void, Never>? {
        if let mutation {
            return mutation
        }
        guard protectedDataAvailable, authorized || monitor != nil || opening != nil else { return nil }
        mutation = Task { [weak self] in
            guard let self else { return }
            defer { mutation = nil }
            guard let monitor = await connection() else { return }
            while protectedDataAvailable {
                let version = revision
                if needsRemoval {
                    await monitor.remove()
                    needsRemoval = false
                } else if authorized, let location = desiredLocation {
                    let center = await monitor.center()
                    guard version == revision else { continue }
                    guard authorized, protectedDataAvailable else { return }
                    if center.map({ $0.distance(from: location) >= Self.radius / 2 }) ?? true {
                        await monitor.replace(location)
                    }
                }
                if version == revision {
                    return
                }
            }
        }
        return mutation
    }

    private static func alwaysSession() -> @MainActor () -> Void {
        let session = CLServiceSession(authorization: .always)
        let diagnostics = Task {
            do {
                for try await diagnostic in session.diagnostics {
                    try Task.checkCancellation()
                    Log.capture.notice(
                        "location session: alwaysDenied=\(diagnostic.alwaysAuthorizationDenied, privacy: .public) denied=\(diagnostic.authorizationDenied, privacy: .public) globallyDenied=\(diagnostic.authorizationDeniedGlobally, privacy: .public) restricted=\(diagnostic.authorizationRestricted, privacy: .public) insufficientlyInUse=\(diagnostic.insufficientlyInUse, privacy: .public)"
                    )
                }
            } catch is CancellationError {
            } catch {
                Log.capture.error("location session diagnostics ended: \(error.localizedDescription)")
            }
        }
        return {
            diagnostics.cancel()
            session.invalidate()
        }
    }
}
