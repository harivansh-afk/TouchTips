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
        let persisted = await monitor.record(for: identifier) != nil
        Log.capture.notice("fence monitor opened: condition=\(persisted ? "persisted" : "missing", privacy: .public)")
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
    private var seed: Task<Void, Never>?
    private var seedGeneration = 0
    private var authorized = false
    private var protectedDataAvailable = false
    private var desiredLocation: CLLocation?
    private var needsRemoval = false
    private var revision = 0
    private var lastFixStatus: FixStatus?
    private var lastConditionStatus: String?

    private enum FixStatus: String {
        case accepted, unauthorized, invalid, coarse, stale, outOfOrder
    }

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
        seed?.cancel()
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
            cancelSeed()
            endSession?()
            endSession = nil
        }
        guard authorized else {
            observation?.cancel()
            return
        }
        // Protected data is a prerequisite for opening the monitor, not for consuming an
        // already-open monitor's events. isProtectedDataAvailable also becomes false on screen lock.
        startObserving()
        if desiredLocation != nil || needsRemoval {
            synchronize()
        }
    }

    /// Reuse a persisted fence until a fresh, accurate fix has moved far enough to justify replacing it.
    func update(_ location: CLLocation, now: Date = .now) {
        guard authorized else { reportFix(.unauthorized); return }
        guard CLLocationCoordinate2DIsValid(location.coordinate), location.horizontalAccuracy >= 0 else {
            reportFix(.invalid)
            return
        }
        guard location.horizontalAccuracy <= Self.radius else { reportFix(.coarse); return }
        guard abs(location.timestamp.timeIntervalSince(now)) <= 120 else { reportFix(.stale); return }
        if let desiredLocation, location.timestamp < desiredLocation.timestamp {
            reportFix(.outOfOrder)
            return
        }
        reportFix(.accepted)
        desiredLocation = location
        revision += 1
        synchronize()
    }

    /// Joins any in-flight add, then removes it. Reset cannot return while an old add can recreate the fence.
    func reset() async {
        cancelSeed()
        desiredLocation = nil
        needsRemoval = true
        revision += 1
        await synchronize()?.value
    }

    /// Called on an eligible foreground start. Coarse presence fixes alone may never establish a
    /// small fence. The provider supplies one bounded precise fix, without delaying contact capture.
    func seedIfNeeded(using fix: @escaping @MainActor () async -> CLLocation?) {
        guard seed == nil, authorized, protectedDataAvailable, desiredLocation == nil else { return }
        seedGeneration += 1
        let generation = seedGeneration
        let version = revision
        seed = Task { [weak self] in
            defer {
                if self?.seedGeneration == generation {
                    self?.seed = nil
                }
            }
            guard let monitor = await self?.connection(), !Task.isCancelled else { return }
            let center = await monitor.center()
            guard center == nil, !Task.isCancelled, self?.authorized == true,
                  self?.revision == version, self?.desiredLocation == nil else { return }
            Log.capture.notice("fence seed: requesting initial fix")
            // Do not retain the owner across this await. Reset and authorization loss cancel the
            // request, and owner release must remain possible even if a provider ignores cancellation.
            let location = await fix()
            guard !Task.isCancelled, let self, authorized,
                  seedGeneration == generation, revision == version, desiredLocation == nil else { return }
            guard let location else {
                Log.capture.notice("fence seed: no fix available")
                return
            }
            update(location)
        }
    }

    private func cancelSeed() {
        seed?.cancel()
        seed = nil
        seedGeneration += 1
    }

    private func connection() async -> CaptureFenceMonitor? {
        if let monitor {
            return monitor
        }
        if let opening {
            return await opening.value
        }
        // CLMonitor persists its records in a protected file. Apple's initial-open requirement
        // does not require an existing monitor to stop observing whenever the device locks.
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
        guard observation == nil, authorized,
              protectedDataAvailable || monitor != nil || opening != nil else { return }
        observation = Task { [weak self] in
            defer {
                self?.observation = nil
                // Permission can be restored before a cancelled iterator has unwound.
                if Task.isCancelled, self?.authorized == true {
                    self?.startObserving()
                }
            }
            guard let monitor = await self?.connection(), self?.authorized == true,
                  !Task.isCancelled else { return }
            do {
                try await monitor.observe { [weak self] in
                    guard let self, authorized else { return }
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
                    reportCondition("removed")
                } else if authorized, let location = desiredLocation {
                    let center = await monitor.center()
                    guard version == revision else { continue }
                    guard authorized, protectedDataAvailable else { return }
                    if center.map({ $0.distance(from: location) >= Self.radius / 2 }) ?? true {
                        await monitor.replace(location)
                        // A replacement is useful evidence even when the previous operation also replaced.
                        lastConditionStatus = nil
                        reportCondition(center == nil ? "created" : "replaced")
                    } else {
                        reportCondition("preserved")
                    }
                }
                if version == revision {
                    return
                }
            }
        }
        return mutation
    }

    private func reportFix(_ status: FixStatus) {
        guard lastFixStatus != status else { return }
        lastFixStatus = status
        Log.capture.notice("fence fix: \(status.rawValue, privacy: .public)")
    }

    private func reportCondition(_ status: String) {
        guard lastConditionStatus != status else { return }
        lastConditionStatus = status
        Log.capture.notice("fence condition: \(status, privacy: .public)")
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
