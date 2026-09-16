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
/// Contacts changes are observed while running. Shortcuts and optional background refresh can catch up.
@MainActor
@Observable
final class CaptureCoordinator: NSObject {
    static let refreshTaskID = "sh.harivan.touchtips.refresh"
    static let lastShortcutCheckKey = "lastShortcutCheck"

    private let database: AppDatabase
    private let notifier: Notifier
    /// Permission support for an explicit foreground Add only; never starts capture services.
    private let manager = CLLocationManager()
    private let contacts: CaptureContacts
    private let refresh: CaptureRefresh
    private let retryDelays: [Duration]
    private let beginBackground: (@escaping @MainActor () -> Void) -> CaptureBackgroundTask
    private var backgroundTask: CaptureBackgroundTask?
    private var backgroundGeneration = 0
    private var tickTask: Task<Void, Never>?
    private var scheduledSource: WakeSource?
    private var tickDeadline: Date?
    @ObservationIgnored private lazy var fence = CaptureFence(wake: {})
    private var hasStarted = false
    private var contactsObserver: (any NSObjectProtocol)?
    private var activeTick: Task<Bool, Never>?
    private var cancelledBatchGeneration = 0
    private var refreshScheduling: Task<Void, Never>?
    /// A wake that arrived mid-tick. Runs once the current one is done.
    private var queuedSource: WakeSource?

    /// When the first contact-change notification of the current burst arrived. The clock for the latency stats.
    private var pendingHeard: Date?

    private(set) var locationStatus: CLAuthorizationStatus
    private(set) var lastTick: Date?
    /// Retained for foreground Add compatibility; automatic visits are disabled.
    private(set) var currentVisit: Visit?
    private(set) var isResetting = false

    /// Fires after anything landed in the database.
    var didIngest: (() -> Void)?

    static let autoCaptureLocationKey = "autoCaptureLocation"
    private let defaults: UserDefaults

    // Compatibility for older UI bindings. Legacy preferences cannot re-enable location capture.
    var autoCaptureLocation: Bool {
        get { false }
        set { defaults.set(false, forKey: Self.autoCaptureLocationKey) }
    }

    var presencePolicy: PresencePolicy {
        get { .off }
        set { defaults.set(PresencePolicy.off.rawValue, forKey: PresencePolicy.key) }
    }

    var locationGranted: Bool {
        locationStatus == .authorizedAlways || locationStatus == .authorizedWhenInUse
    }

    var locationPermissionAction: LocationPermissionAction {
        locationGranted ? .allowed : LocationPermissionAction(status: locationStatus)
    }

    init(
        database: AppDatabase, notifier: Notifier, contacts: CaptureContacts = .system,
        location: CaptureLocation? = nil, refresh: CaptureRefresh = .system,
        retryDelays: [Duration] = [.seconds(2), .seconds(5)],
        defaults: UserDefaults = .standard,
        beginBackground: @escaping (@escaping @MainActor () -> Void) -> CaptureBackgroundTask = {
            CaptureBackgroundTask(expiration: $0)
        }
    ) {
        self.defaults = defaults
        defaults.set(false, forKey: Self.autoCaptureLocationKey)
        defaults.set(PresencePolicy.off.rawValue, forKey: PresencePolicy.key)
        self.database = database

        self.notifier = notifier
        self.contacts = contacts
        self.refresh = refresh
        self.retryDelays = retryDelays
        self.beginBackground = beginBackground
        locationStatus = manager.authorizationStatus

        super.init()
    }

    /// Headless startup must not silently establish a baseline before the explicit check preflight.
    func start(checkOnLaunch: Bool = true) {
        guard !hasStarted else { return }
        hasStarted = true
        if checkOnLaunch { scheduleTick(.launch, after: 0) }
        manager.delegate = self
        manager.stopMonitoringVisits()
        manager.stopMonitoringSignificantLocationChanges()
        restoreFence()
        scheduleRefresh()
        if checkOnLaunch { startObservingContacts() }
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

    /// Explicit Shortcuts check. A silent first snapshot must be completed in the app first.
    func checkForNewContacts() async throws -> ContactCheckResult {
        guard !Task.isCancelled else { throw ContactCheckError.cancelled }
        guard contacts.authorized() else { throw ContactCheckError.contactsAccessRequired }
        guard !isResetting else { throw ContactCheckError.setupRequired }
        let token: Data?
        do {
            token = try await database.reader.read { db in try db.value(for: .contactsHistoryToken) }
        } catch {
            throw ContactCheckError.scanFailed
        }
        guard !Task.isCancelled else { throw ContactCheckError.cancelled }
        guard token != nil, !isResetting else { throw ContactCheckError.setupRequired }
        let cancellationGeneration = cancelledBatchGeneration
        let success = await tick(.intent)
        guard !Task.isCancelled, cancellationGeneration == cancelledBatchGeneration else {
            throw ContactCheckError.cancelled
        }
        guard contacts.authorized() else { throw ContactCheckError.contactsAccessRequired }
        guard success else { throw ContactCheckError.scanFailed }
        let checkedAt = Date()
        defaults.set(checkedAt.timeIntervalSince1970, forKey: Self.lastShortcutCheckKey)
        return ContactCheckResult(checkedAt: checkedAt)
    }

    /// Diff, atomically ingest, and drain the outbox. All callers await the same full scan batch.
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
                if Task.isCancelled { cancelledBatchGeneration += 1 }
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

        cancelScheduledTick()
        queuedSource = nil
        if let activeTick {
            activeTick.cancel()
            _ = await activeTick.value
        }
        endBackgroundIfIdle()

        await notifier.cancelDelivery()
        await fence.reset()
        do {
            try Ingest.deleteAll(database)
        } catch {
            isResetting = false
            throw error
        }
        currentVisit = nil
        lastTick = nil
        pendingHeard = nil
        defaults.removeObject(forKey: Self.lastShortcutCheckKey)
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

        record(source, at: now)

        let database = database
        do {
            let token = try await database.reader.read { db in try db.value(for: .contactsHistoryToken) }
            // Headless invocations and observers cannot establish the initial silent snapshot.
            if token == nil, source != .foreground, source != .user, source != .launch {
                await notifier.deliverPending()
                return false
            }
            let changes = try await contacts.changes(token)
            try Task.checkCancellation()
            // Permission can change while the asynchronous Contacts read is in flight.
            // Never reconcile a newly limited view as a full-store deletion snapshot.
            guard contacts.authorized() else { throw ContactCheckError.contactsAccessRequired }
            let summary = try await Task.detached(priority: .utility) {
                try Ingest.apply(changes, now: now, expectedToken: token, useLocationEvidence: false, to: database)
            }.value
            let resolvedAt = Date()
            lastTick = now
            Log.capture.notice(
                "tick \(source.rawValue, privacy: .public): \(summary.newPeople, privacy: .public) new, \(summary.snapshotted, privacy: .public) snapshotted, \(summary.updated, privacy: .public) updated, \(summary.deleted, privacy: .public) deleted, \(Self.ms(since: now), privacy: .public)"
            )
            if summary != IngestSummary() {
                didIngest?()
            }

            // Reconcile deletions before draining. Location and place naming cannot delay this commit or alert.
            await notifier.deliverPending(timing: NoticeTiming(
                heard: heard, ticked: now, resolved: resolvedAt, posted: resolvedAt
            ))

            return !Task.isCancelled
        } catch {
            Log.capture.error("tick failed: \(error.localizedDescription)")
            // A Contacts read failure must not prevent already-durable notices from being retried.
            await notifier.deliverPending()
            return false
        }
    }

    /// Legacy debug action. Automatic location evidence is disabled, including explicit witnesses.
    func witness() async -> Bool { false }

    // MARK: - Notify

    private static func ms(since start: Date) -> String {
        "\(Int(Date().timeIntervalSince(start) * 1000)) ms"
    }

    /// "3.2 s: coalesce 0.3, fix 1.9, resolve 0.1, name 0.8, post 0.0"
    static func describe(_ timing: NoticeTiming) -> String {
        let stages = timing.stages.map { "\($0.name) \($0.seconds.formatted(.number.precision(.fractionLength(1))))" }
        return "\(timing.total.formatted(.number.precision(.fractionLength(1)))) s: \(stages.joined(separator: ", "))"
    }

    // MARK: - Foreground

    func foreground() {
        startObservingContacts()
        scheduleTick(.foreground, after: 0)
        locationStatus = manager.authorizationStatus
        restoreFence()
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

    /// Migration only: remove the persisted TouchedTipsFence/breadcrumb once protected data is available.
    /// Disabled configuration opens no Always session and observes no event stream.
    func restoreFence() {
        guard hasStarted else { return }
        fence.configure(
            authorized: false,
            protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable,
            enabled: false
        )
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

    func record(_ live: LiveVisit) {}
}

extension CaptureCoordinator: CLLocationManagerDelegate {
    // CoreLocation calls back on the thread that created the manager, which is the main thread here.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let managerID = ObjectIdentifier(manager)
        MainActor.assumeIsolated {
            guard managerID == ObjectIdentifier(self.manager) else { return }
            locationStatus = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {}

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Log.capture.error("location: \(error.localizedDescription)")
    }
}
