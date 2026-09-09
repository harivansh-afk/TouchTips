import BackgroundTasks
import Contacts
import CoreLocation
import Observation
import TouchTipsCore
import UIKit

@MainActor
struct CaptureContacts {
    var authorized: () -> Bool
    var changes: (Data?) async throws -> ContactChangeSet

    static var system: Self {
        let diff = ContactsDiff()
        return Self(
            authorized: { CNContactStore.authorizationStatus(for: .contacts) == .authorized },
            changes: { try await diff.changes(since: $0) }
        )
    }
}

@MainActor
struct CaptureLocation {
    var authorized: () -> Bool
    var fix: (Duration) async -> CLLocation?

    static var system: Self {
        let oneShot = OneShotLocation()
        return Self(
            authorized: {
                let status = CLLocationManager().authorizationStatus
                return status == .authorizedAlways || status == .authorizedWhenInUse
            },
            fix: { await oneShot.fix(timeout: $0) }
        )
    }
}

@MainActor
struct CaptureRefresh {
    var pending: () async -> [BGTaskRequest]
    var submit: (BGTaskRequest) throws -> Void

    static var system: Self {
        Self(
            pending: { await BGTaskScheduler.shared.pendingTaskRequests() },
            submit: { try BGTaskScheduler.shared.submit($0) }
        )
    }
}

/// Every way the app wakes lands here, runs one tick, and posts one notification per new person.
///
/// Contacts changes are observed while running. Location events and background refresh offer additional
/// opportunities to catch up; iOS decides when a suspended process can run again.
@MainActor
@Observable
final class CaptureCoordinator: NSObject {
    static let refreshTaskID = "sh.harivan.touchtips.refresh"
    private static let heartbeatInterval: TimeInterval = 5 * 60
    /// A heartbeat later than this means the process was suspended in between.
    private static let gapTolerance: TimeInterval = heartbeatInterval * 1.5
    private static let fixTimeout: Duration = .seconds(8)

    private let database: AppDatabase
    private let notifier: Notifier
    /// Only visits and significant-change monitoring use this manager, so its location callbacks
    /// can establish a standard session after a significant-change background launch.
    private let manager = CLLocationManager()
    private let presence = CapturePresence()
    private let location: CaptureLocation
    private let contacts: CaptureContacts
    private let refresh: CaptureRefresh
    private let retryDelays: [Duration]
    private let beginBackground: (@escaping @MainActor () -> Void) -> CaptureBackgroundTask
    private var backgroundTask: CaptureBackgroundTask?
    private var backgroundGeneration = 0
    private var tickTask: Task<Void, Never>?
    private var scheduledSource: WakeSource?
    private var tickDeadline: Date?
    private var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored private lazy var fence = CaptureFence { [weak self] in self?.scheduleTick(.fence, after: 0) }
    private var hasStarted = false
    private var contactsObserver: (any NSObjectProtocol)?
    private var activeTick: Task<Bool, Never>?
    private var enrichmentTask: Task<Void, Never>?
    private var refreshScheduling: Task<Void, Never>?
    /// A wake that arrived mid-tick. Runs once the current one is done.
    private var queuedSource: WakeSource?
    private var lastLocation: CLLocation?
    /// When the first contact-change notification of the current burst arrived. The clock for the latency stats.
    private var pendingHeard: Date?
    private var lastHeartbeat = Date()

    private(set) var locationStatus: CLAuthorizationStatus
    private(set) var lastTick: Date?
    /// The visit we are in right now, if CoreLocation has told us about it.
    private(set) var currentVisit: Visit?
    private(set) var isResetting = false
    private var resetGeneration = 0
    /// Fires after anything landed in the database.
    var didIngest: (() -> Void)?

    static let autoCaptureLocationKey = "autoCaptureLocation"
    private let defaults: UserDefaults

    var autoCaptureLocation: Bool {
        didSet {
            defaults.set(autoCaptureLocation, forKey: Self.autoCaptureLocationKey)
            if !autoCaptureLocation {
                enrichmentTask?.cancel()
                currentVisit = nil
                lastLocation = nil
            }
            if autoCaptureLocation, presencePolicy == .off {
                presencePolicy = .always
            }
            applyLocationServices()
        }
    }

    var presencePolicy: PresencePolicy {
        didSet {
            defaults.set(presencePolicy.rawValue, forKey: PresencePolicy.key)
            applyPresence()
        }
    }

    var locationGranted: Bool {
        locationStatus == .authorizedAlways
    }

    var locationPermissionAction: LocationPermissionAction {
        LocationPermissionAction(status: locationStatus)
    }

    init(
        database: AppDatabase, notifier: Notifier, contacts: CaptureContacts = .system,
        location: CaptureLocation = .system, refresh: CaptureRefresh = .system,
        retryDelays: [Duration] = [.seconds(2), .seconds(5)],
        defaults: UserDefaults = .standard,
        beginBackground: @escaping (@escaping @MainActor () -> Void) -> CaptureBackgroundTask = {
            CaptureBackgroundTask(expiration: $0)
        }
    ) {
        self.defaults = defaults
        // Preserve existing capture unless the user previously chose Off in the dev picker.
        autoCaptureLocation = defaults.object(forKey: Self.autoCaptureLocationKey) as? Bool
            ?? (defaults.string(forKey: PresencePolicy.key) != PresencePolicy.off.rawValue)
        self.database = database

        self.notifier = notifier
        self.contacts = contacts
        self.location = location
        self.refresh = refresh
        self.retryDelays = retryDelays
        self.beginBackground = beginBackground
        locationStatus = manager.authorizationStatus
        presencePolicy = defaults.string(forKey: PresencePolicy.key).flatMap(PresencePolicy.init) ?? .always
        super.init()
    }

    /// Call once at launch, every launch, before `didFinishLaunching` returns. Setting the delegate again is
    /// what lets CoreLocation deliver the event that relaunched a terminated app. AppDelegate registers
    /// background refresh separately, so storage recovery can safely start capture later.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        scheduleTick(.launch, after: 0)
        manager.delegate = self
        presence.manager.delegate = self
        applyLocationServices()
        startHeartbeat()
        scheduleRefresh()
        startObservingContacts()
    }

    func startObservingContacts() {
        guard contactsObserver == nil else { return }
        contactsObserver = NotificationCenter.default.addObserver(
            forName: .CNContactStoreDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            // One save posts several of these. A short coalesce turns them into one tick.
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.pendingHeard == nil {
                    self.pendingHeard = Date()
                    Log.capture.notice("contacts changed")
                }
                self.scheduleTick(.contacts, after: 0.3)
            }
        }
    }

    func stopObservingContacts() {
        if let contactsObserver {
            NotificationCenter.default.removeObserver(contactsObserver)
        }
        contactsObserver = nil
        cancelScheduledTick()
        endBackgroundIfIdle()
    }

    private func cancelScheduledTick() {
        tickTask?.cancel()
        tickTask = nil
        scheduledSource = nil
        tickDeadline = nil
    }

    func requestLocation() {
        guard locationPermissionAction == .request else { return }
        manager.requestWhenInUseAuthorization()
    }

    func scheduleTick(_ source: WakeSource, after delay: TimeInterval = 0) {
        guard !isResetting else { return }
        // Keep this synchronous with the system callback. The process can suspend during a debounce.
        retainBackgroundTask()
        if activeTick != nil {
            queue(source)
            return
        }
        if scheduledSource != .contacts {
            scheduledSource = source
        }
        let deadline = Date(timeIntervalSinceNow: delay)
        // Coalesce toward the earliest requested scan. A busy sync cannot postpone discovery forever.
        if tickTask != nil, let tickDeadline, tickDeadline <= deadline {
            return
        }
        tickTask?.cancel()
        tickDeadline = deadline
        tickTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            let next = scheduledSource ?? source
            tickTask = nil
            scheduledSource = nil
            tickDeadline = nil
            await tick(next)
        }
    }

    /// Diff the contact store, witness any add with a fix, resolve, notify. Safe to call repeatedly.
    @discardableResult
    func tick(_ source: WakeSource) async -> Bool {
        guard !isResetting, !Task.isCancelled else { return false }
        retainBackgroundTask()
        if let activeTick {
            queue(source)
            return await withTaskCancellationHandler {
                await activeTick.value
            } onCancel: { activeTick.cancel() }
        }
        let firstSource = scheduledSource == .contacts ? .contacts : source
        cancelScheduledTick()
        let work = Task { [weak self] in
            guard let self else { return false }
            defer {
                activeTick = nil
                // A foreground/contact wake may arrive while expired work is unwinding.
                if Task.isCancelled, let queuedSource, !isResetting {
                    self.queuedSource = nil
                    scheduleTick(queuedSource, after: 0)
                }
                endBackgroundIfIdle()
            }
            var success = true
            var retries = retryDelays.makeIterator()
            var next: WakeSource? = firstSource
            while let source = next, !Task.isCancelled {
                queuedSource = nil
                let completed = await performTick(source)
                success = completed
                next = queuedSource
                if next == nil, !completed, contacts.authorized(), !Task.isCancelled,
                   let delay = retries.next() {
                    do { try await Task.sleep(for: delay) } catch { break }
                    next = queuedSource ?? source
                }
            }
            return success && !Task.isCancelled
        }
        activeTick = work
        return await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }

    private func queue(_ source: WakeSource) {
        if queuedSource != .contacts {
            queuedSource = source
        }
    }

    private func retainBackgroundTask() {
        guard backgroundTask == nil else { return }
        backgroundGeneration += 1
        let generation = backgroundGeneration
        backgroundTask = beginBackground { [weak self] in
            guard let self, backgroundGeneration == generation else { return }
            // Expiration abandons this batch. Only a later external wake may schedule fresh work.
            cancelScheduledTick()
            queuedSource = nil
            activeTick?.cancel()
            backgroundTask?.end()
            backgroundTask = nil
        }
    }

    private func endBackgroundIfIdle() {
        guard tickTask == nil, activeTick == nil else { return }
        backgroundTask?.end()
        backgroundTask = nil
    }

    /// Finish any old-token work before erasing its cursor, then read a fresh Contacts baseline.
    func reset() async throws {
        guard !isResetting else { return }
        isResetting = true
        resetGeneration += 1
        cancelScheduledTick()
        queuedSource = nil
        if let activeTick {
            activeTick.cancel()
            _ = await activeTick.value
        }
        endBackgroundIfIdle()
        enrichmentTask?.cancel()
        await enrichmentTask?.value
        await notifier.cancelDelivery()
        await fence.reset()
        do {
            try Ingest.deleteAll(database)
        } catch {
            isResetting = false
            throw error
        }
        currentVisit = nil
        lastLocation = nil
        lastTick = nil
        pendingHeard = nil
        lastHeartbeat = Date()
        applyPresence()
        didIngest?()
        isResetting = false
        await tick(.user)
    }

    private func performTick(_ source: WakeSource) async -> Bool {
        restoreFence()

        guard contacts.authorized() else {
            Log.capture.notice("capture skipped: full Contacts access unavailable")
            await notifier.deliverPending()
            return false
        }

        let now = Date()
        let heard = pendingHeard ?? now
        pendingHeard = nil
        let continuous = now.timeIntervalSince(lastHeartbeat) <= Self.gapTolerance
        lastHeartbeat = now
        record(source, at: now)

        let database = database
        do {
            let token = try await database.reader.read { db in try db.value(for: .contactsHistoryToken) }
            let changes = try await contacts.changes(token)
            try Task.checkCancellation()
            let summary = try await Task.detached(priority: .utility) {
                try Ingest.apply(changes, now: now, to: database)
            }.value
            let resolvedAt = Date()
            lastTick = now
            Log.capture.notice(
                "tick \(source.rawValue, privacy: .public): \(summary.newPeople, privacy: .public) new, \(summary.snapshotted, privacy: .public) snapshotted, \(summary.updated, privacy: .public) updated, \(summary.deleted, privacy: .public) deleted, \(Self.ms(since: now), privacy: .public)"
            )
            if summary != IngestSummary() {
                didIngest?()
            }
            if source == .contacts, continuous, token != nil, !changes.isSnapshot, !summary.added.isEmpty {
                enrich(at: now)
            }
            // Reconcile deletions before draining. Location and place naming cannot delay this commit or alert.
            await notifier.deliverPending(timing: NoticeTiming(
                heard: heard, ticked: now, resolved: resolvedAt, posted: resolvedAt
            ))
            rearmFence(at: lastLocation)
            return !Task.isCancelled
        } catch {
            Log.capture.error("tick failed: \(error.localizedDescription)")
            // A Contacts read failure must not prevent already-durable notices from being retried.
            await notifier.deliverPending()
            return false
        }
    }

    private func enrich(at now: Date) {
        guard autoCaptureLocation, enrichmentTask == nil, location.authorized() else { return }
        let generation = resetGeneration
        enrichmentTask = Task { [weak self] in
            guard let self else { return }
            defer { enrichmentTask = nil }
            guard let fix = await location.fix(Self.fixTimeout), !Task.isCancelled,
                  !isResetting, autoCaptureLocation, generation == resetGeneration,
                  fix.horizontalAccuracy >= 0,
                  abs(fix.timestamp.timeIntervalSince(now)) <= Resolver.fixWindow else { return }
            do {
                try Ingest.recordFix(LiveFix(
                    latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude,
                    accuracyMeters: fix.horizontalAccuracy, at: now
                ), now: .now, to: database)
                lastLocation = fix
                didIngest?()
                rearmFence(at: fix)
                Log.capture.notice("location enrichment completed after \(Self.ms(since: now), privacy: .public)")
            } catch {
                Log.capture.error("location enrichment failed: \(error.localizedDescription)")
            }
        }
    }

    /// Mark where the phone is right now. The next add inside the window is witnessed by it.
    func witness() async -> Bool {
        let generation = resetGeneration
        guard !isResetting, let location = await location.fix(Self.fixTimeout),
              !isResetting, generation == resetGeneration else { return false }
        lastLocation = location
        let now = Date()
        let fix = LiveFix(
            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
            accuracyMeters: location.horizontalAccuracy, at: now
        )
        do {
            try Ingest.recordFix(fix, now: now, to: database)
        } catch {
            Log.capture.error("fix not recorded: \(error.localizedDescription)")
            return false
        }
        didIngest?()
        rearmFence(at: location)
        return true
    }

    // MARK: - Notify

    private static func ms(since start: Date) -> String {
        "\(Int(Date().timeIntervalSince(start) * 1000)) ms"
    }

    /// "3.2 s: coalesce 0.3, fix 1.9, resolve 0.1, name 0.8, post 0.0"
    static func describe(_ timing: NoticeTiming) -> String {
        let stages = timing.stages.map { "\($0.name) \($0.seconds.formatted(.number.precision(.fractionLength(1))))" }
        return "\(timing.total.formatted(.number.precision(.fractionLength(1)))) s: \(stages.joined(separator: ", "))"
    }

    // MARK: - Presence

    func foreground() {
        scheduleTick(.foreground, after: 0)
        locationStatus = manager.authorizationStatus
        applyLocationServices(restartPresence: true)
    }

    private func applyLocationServices(restartPresence: Bool = false) {
        guard hasStarted else { return }
        restoreFence()
        if autoCaptureLocation, locationGranted, UIApplication.shared.applicationState == .active {
            // A missing fence gets one bounded foreground fix; capture and notification delivery never wait.
            fence.seedIfNeeded { [location] in await location.fix(Self.fixTimeout) }
        }
        if autoCaptureLocation, locationStatus == .authorizedAlways || locationStatus == .authorizedWhenInUse {
            manager.startMonitoringVisits()
            manager.startMonitoringSignificantLocationChanges()
        } else {
            manager.stopMonitoringVisits()
            manager.stopMonitoringSignificantLocationChanges()
        }
        applyPresence(restart: restartPresence)
    }

    /// Background location offers more chances to scan. It does not guarantee continuous execution
    /// or control which radios the system uses.
    private func applyPresence(restart: Bool = false, significantChangeWake: Bool = false) {
        guard hasStarted else { return }
        let wanted: Bool = switch presencePolicy {
        case .always: locationStatus == .authorizedAlways
        case .atPlaces: locationStatus == .authorizedAlways && currentVisit != nil
        case .off: false
        }
        presence.update(
            enabled: autoCaptureLocation && wanted, applicationState: UIApplication.shared.applicationState,
            restart: restart, significantChangeWake: significantChangeWake
        )
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.heartbeatInterval))
                guard !Task.isCancelled, let self else { return }
                self.beat()
            }
        }
    }

    private func beat() {
        let now = Date()
        lastHeartbeat = now
        record(.presence, at: now)
        scheduleTick(.presence, after: 0)
    }

    private func record(_ source: WakeSource, at now: Date) {
        do {
            try Ingest.recordHeartbeat(source, at: now, batteryLevel: Self.batteryLevel, to: database)
        } catch {
            Log.capture.error("heartbeat not recorded: \(error.localizedDescription)")
        }
    }

    private static var batteryLevel: Double? {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        return level < 0 ? nil : Double(level)
    }

    // MARK: - Fence

    /// Called on launch, foregrounding, protected-data availability and later system wakes.
    /// Reuses the monitor and restores an event stream that ended after a permission/storage interruption.
    func restoreFence() {
        guard hasStarted else { return }
        fence.configure(
            authorized: locationStatus == .authorizedAlways,
            protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable,
            enabled: autoCaptureLocation
        )
    }

    private func rearmFence(at location: CLLocation?) {
        guard hasStarted, autoCaptureLocation, !isResetting, let location else { return }
        fence.update(location)
    }

    // MARK: - Refresh

    func handleRefresh(_ task: BGTask) {
        scheduleRefresh()
        let work = Task { [weak self] in await self?.tick(.refresh) }
        task.expirationHandler = { work.cancel() }
        Task {
            let success = await work.value ?? false
            task.setTaskCompleted(success: success && !work.isCancelled)
        }
    }

    @discardableResult
    func scheduleRefresh() -> Task<Void, Never> {
        if let refreshScheduling {
            return refreshScheduling
        }
        let work = Task { [weak self] in
            guard let self else { return }
            defer { refreshScheduling = nil }
            let pending = await refresh.pending()
            // Submission replaces an existing request. Never postpone an earlier eligible refresh.
            let earliest = Date(timeIntervalSinceNow: 15 * 60)
            if pending.contains(where: {
                $0.identifier == Self.refreshTaskID && ($0.earliestBeginDate ?? .distantPast) <= earliest
            }) {
                return
            }
            let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
            request.earliestBeginDate = earliest
            do {
                try refresh.submit(request)
            } catch {
                Log.capture.notice("refresh not scheduled: \(error.localizedDescription)")
            }
        }
        refreshScheduling = work
        return work
    }

    // MARK: - Location events

    func record(_ live: LiveVisit) {
        guard autoCaptureLocation, !isResetting else { return }
        scheduleTick(.visit, after: 0)
        do {
            let visit = try Ingest.recordLiveVisit(live, now: .now, to: database)
            currentVisit = visit.isOngoing ? visit : nil
            didIngest?()
        } catch {
            Log.capture.error("visit not recorded: \(error.localizedDescription)")
        }
        applyPresence()
    }

    /// Presence updates and significant changes both provide an execution opportunity.
    private func moved(to location: CLLocation?) {
        guard autoCaptureLocation, !isResetting else { return }
        // Even a cached or imprecise location is a chance to catch up on Contacts while iOS grants CPU.
        scheduleTick(.movement, after: 0)
        guard let location, location.horizontalAccuracy >= 0,
              CLLocationCoordinate2DIsValid(location.coordinate),
              lastLocation.map({ location.timestamp >= $0.timestamp }) ?? true else { return }
        lastLocation = location
        // The scan rearms the fence after committing and submitting any pending notifications.
    }
}

extension CaptureCoordinator: CLLocationManagerDelegate {
    // CoreLocation calls back on the thread that created the manager, which is the main thread here.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let managerID = ObjectIdentifier(manager)
        MainActor.assumeIsolated {
            guard managerID == ObjectIdentifier(self.manager) else { return }
            locationStatus = status
            applyLocationServices()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let live = LiveVisit(
            latitude: visit.coordinate.latitude,
            longitude: visit.coordinate.longitude,
            accuracyMeters: visit.horizontalAccuracy,
            arrival: visit.arrivalDate,
            departure: visit.departureDate == .distantFuture ? nil : visit.departureDate
        )
        MainActor.assumeIsolated { record(live) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let managerID = ObjectIdentifier(manager)
        MainActor.assumeIsolated {
            moved(to: locations.last)
            if managerID == ObjectIdentifier(self.manager) {
                applyPresence(significantChangeWake: true)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Log.capture.error("location: \(error.localizedDescription)")
    }
}
