import BackgroundTasks
import Contacts
import CoreLocation
import Observation
import TouchedTipsCore
import UIKit

/// Every way the app wakes lands here, runs one tick, and posts one notification per new person.
///
/// Presence keeps the process resident so a contact change is heard the moment it happens. Visits,
/// significant changes, a breadcrumb fence and a refresh floor bring the process back when iOS kills it.
@MainActor
@Observable
final class CaptureCoordinator: NSObject {
    static let refreshTaskID = "sh.harivan.touchtips.refresh"
    /// CLMonitor rejects anything but letters and digits in the name; it becomes a file under Library.
    private static let fenceName = "TouchedTipsFence"
    private static let fenceID = "breadcrumb"
    private static let fenceRadius: CLLocationDistance = 150
    private static let heartbeatInterval: TimeInterval = 5 * 60
    /// A heartbeat later than this means the process was suspended in between.
    private static let gapTolerance: TimeInterval = heartbeatInterval * 1.5
    private static let fixTimeout: Duration = .seconds(8)

    private let database: AppDatabase
    private let notifier: Notifier
    private let manager = CLLocationManager()
    private let oneShot = OneShotLocation()
    private var tickTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var fenceTask: Task<Void, Never>?
    private var monitor: CLMonitor?
    private var contactsObserver: (any NSObjectProtocol)?
    private var presenceActive = false
    private var ticking = false
    /// A wake that arrived mid-tick. Runs once the current one is done.
    private var queuedSource: WakeSource?
    private var lastLocation: CLLocation?
    /// When the first contact-change notification of the current burst arrived. The clock for the latency stats.
    private var pendingHeard: Date?
    /// Start of the current unbroken stretch of running. Moves forward whenever a gap shows the process was suspended.
    private var aliveSince = Date()
    private var lastHeartbeat = Date()

    private(set) var locationStatus: CLAuthorizationStatus
    private(set) var lastTick: Date?
    /// The visit we are in right now, if CoreLocation has told us about it.
    private(set) var currentVisit: Visit?
    /// Fires after anything landed in the database.
    var didIngest: (() -> Void)?

    var presencePolicy: PresencePolicy {
        didSet {
            UserDefaults.standard.set(presencePolicy.rawValue, forKey: PresencePolicy.key)
            applyPresence()
        }
    }

    var locationGranted: Bool { locationStatus == .authorizedAlways }

    init(database: AppDatabase, notifier: Notifier) {
        self.database = database
        self.notifier = notifier
        locationStatus = manager.authorizationStatus
        presencePolicy = PresencePolicy.stored
        super.init()
    }

    /// Call once at launch, every launch, before `didFinishLaunching` returns. Setting the delegate again is
    /// what lets CoreLocation deliver the event that relaunched a terminated app; registering the refresh
    /// task any later is an error.
    func start() {
        manager.delegate = self
        applyLocationServices()
        startFence()
        startHeartbeat()
        registerRefresh()
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
        // Give a launch-time visit a moment to land so the add it explains gets a place on the first pass.
        scheduleTick(.launch, after: 2)
    }

    func requestLocation() {
        switch locationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    func scheduleTick(_ source: WakeSource, after delay: TimeInterval = 0.3) {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.tick(source)
        }
    }

    /// Diff the contact store, witness any add with a fix, resolve, notify. Safe to call repeatedly.
    func tick(_ source: WakeSource) async {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return }
        if ticking {
            queuedSource = source
            return
        }
        ticking = true
        let background = UIApplication.shared.beginBackgroundTask()
        defer {
            UIApplication.shared.endBackgroundTask(background)
            ticking = false
            if let next = queuedSource {
                queuedSource = nil
                scheduleTick(next, after: 0)
            }
        }

        let now = Date()
        let heard = pendingHeard ?? now
        pendingHeard = nil
        var fixedAt: Date?
        let continuous = now.timeIntervalSince(lastHeartbeat) <= Self.gapTolerance
        if !continuous { aliveSince = now }
        lastHeartbeat = now
        record(source, at: now)

        let database = database
        do {
            let token = try await database.reader.read { db in try db.value(for: .contactsHistoryToken) }
            let changes = try await Task.detached(priority: .utility) { try ContactsDiff().changes(since: token) }.value

            // Only a real add is worth a precise fix. The first run is a snapshot, not a meeting.
            if token != nil, !changes.added.isEmpty, locationStatus != .denied, locationStatus != .restricted,
               let location = await oneShot.fix(timeout: Self.fixTimeout)
            {
                lastLocation = location
                fixedAt = Date()
                Log.capture.notice("fix ±\(Int(location.horizontalAccuracy), privacy: .public) m after \(Self.ms(since: now), privacy: .public)")
                let fix = LiveFix(
                    latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                    accuracyMeters: location.horizontalAccuracy, at: now
                )
                try Ingest.recordFix(fix, now: now, to: database)
            }

            // A change heard by a continuously running process cannot predate the moment it came alive.
            let narrow = source == .contacts && continuous ? aliveSince : nil
            let summary = try await Task.detached(priority: .utility) {
                try Ingest.apply(changes, now: now, aliveSince: narrow, to: database)
            }.value
            let resolvedAt = Date()
            lastTick = now
            Log.capture.notice(
                "tick \(source.rawValue, privacy: .public): \(summary.newPeople, privacy: .public) new, \(summary.snapshotted, privacy: .public) snapshotted, \(summary.updated, privacy: .public) updated, \(summary.deleted, privacy: .public) deleted, \(Self.ms(since: now), privacy: .public)"
            )
            if summary != IngestSummary() { didIngest?() }
            if !summary.added.isEmpty {
                await notify(summary.added, heard: heard, ticked: now, fixed: fixedAt, resolved: resolvedAt)
            }
        } catch {
            Log.capture.error("tick failed: \(error.localizedDescription)")
        }
        rearmFence(at: lastLocation)
    }

    /// Mark where the phone is right now. The next add inside the window is witnessed by it.
    func witness() async -> Bool {
        guard let location = await oneShot.fix(timeout: Self.fixTimeout) else { return false }
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

    private func notify(_ contactIDs: [String], heard: Date, ticked: Date, fixed: Date?, resolved: Date) async {
        for contactID in contactIDs {
            guard let row = try? await database.reader.read({ db in try Person.row(contactID: contactID).fetchOne(db) }) else { continue }
            var placeName = row.place?.name
            if placeName == nil, let place = row.place, let placeID = place.id {
                placeName = await Self.name(place)
                if let placeName {
                    _ = try? await database.writer.write { db in
                        try Place.filter(key: placeID).updateAll(
                            db, Place.Columns.name.set(to: placeName), Place.Columns.namedAt.set(to: Date())
                        )
                    }
                }
            }
            let namedAt = Date()
            await notifier.postMeet(contactID: contactID, name: row.person.name, at: row.meet?.start, placeName: placeName)
            let timing = NoticeTiming(
                heard: heard, ticked: ticked, fixed: fixed, resolved: resolved, named: namedAt, posted: Date()
            )
            Log.capture.notice("notified \(row.person.name, privacy: .private): \(Self.describe(timing), privacy: .public)")
            try? await database.writer.write { db in
                try db.setValue(try timing.encoded(), for: .lastNotice)
            }
        }
    }

    private static func ms(since start: Date) -> String {
        "\(Int(Date().timeIntervalSince(start) * 1000)) ms"
    }

    /// "3.2 s: coalesce 0.3, fix 1.9, resolve 0.1, name 0.8, post 0.0"
    static func describe(_ timing: NoticeTiming) -> String {
        let stages = timing.stages.map { "\($0.name) \($0.seconds.formatted(.number.precision(.fractionLength(1))))" }
        return "\(timing.total.formatted(.number.precision(.fractionLength(1)))) s: \(stages.joined(separator: ", "))"
    }

    /// The business at the fix if there is one within a few doors, else the address.
    private static func name(_ place: Place) async -> String? {
        let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        if let poi = try? await NearbyPlaces.around(coordinate, radius: 75, limit: 1).first { return poi.name }
        return (try? await Geocoder.reverseGeocode(latitude: place.latitude, longitude: place.longitude))?.title
    }

    // MARK: - Presence

    private func applyLocationServices() {
        guard locationStatus == .authorizedAlways || locationStatus == .authorizedWhenInUse else { return }
        manager.startMonitoringVisits()
        manager.startMonitoringSignificantLocationChanges()
        applyPresence()
    }

    /// A low-power location session is what keeps iOS from suspending the process. GPS stays off; fixes
    /// come from cell and Wi-Fi. Automatic pausing is off on purpose: standing still is exactly when a
    /// new contact tends to appear.
    private func applyPresence() {
        let wanted: Bool
        switch presencePolicy {
        case .always: wanted = locationStatus == .authorizedAlways
        case .atPlaces: wanted = locationStatus == .authorizedAlways && currentVisit != nil
        case .off: wanted = false
        }
        guard wanted != presenceActive else { return }
        presenceActive = wanted
        if wanted {
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
            manager.showsBackgroundLocationIndicator = false
            manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
            manager.distanceFilter = kCLDistanceFilterNone
            manager.activityType = .other
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates = false
        }
        Log.capture.notice("presence \(wanted ? "on" : "off", privacy: .public)")
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
        if now.timeIntervalSince(lastHeartbeat) > Self.gapTolerance { aliveSince = now }
        lastHeartbeat = now
        record(.presence, at: now)
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

    /// One small region around wherever the phone last was. Leaving it is a wake, and the place you just
    /// left is the place for anything that appeared meanwhile.
    private func startFence() {
        fenceTask?.cancel()
        fenceTask = Task { [weak self] in
            let monitor = await CLMonitor(Self.fenceName)
            guard let self else { return }
            self.monitor = monitor
            do {
                for try await event in await monitor.events {
                    guard event.identifier == Self.fenceID, event.state == .unsatisfied else { continue }
                    self.scheduleTick(.fence, after: 0.5)
                }
            } catch {
                Log.capture.error("fence: \(error.localizedDescription)")
            }
        }
    }

    private func rearmFence(at location: CLLocation?) {
        guard let location, let monitor, locationStatus == .authorizedAlways else { return }
        Task {
            let condition = CLMonitor.CircularGeographicCondition(center: location.coordinate, radius: Self.fenceRadius)
            await monitor.remove(Self.fenceID)
            await monitor.add(condition, identifier: Self.fenceID, assuming: .satisfied)
        }
    }

    // MARK: - Refresh

    private func registerRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: .main) { [weak self] task in
            MainActor.assumeIsolated { self?.handleRefresh(task) }
        }
        scheduleRefresh()
    }

    private func handleRefresh(_ task: BGTask) {
        scheduleRefresh()
        let work = Task { [weak self] in await self?.tick(.refresh) }
        task.expirationHandler = { work.cancel() }
        Task {
            await work.value
            task.setTaskCompleted(success: true)
        }
    }

    private func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Log.capture.notice("refresh not scheduled: \(error.localizedDescription)")
        }
    }

    // MARK: - Location events

    private func record(_ live: LiveVisit) {
        do {
            let visit = try Ingest.recordLiveVisit(live, now: .now, to: database)
            currentVisit = visit.isOngoing ? visit : nil
            didIngest?()
        } catch {
            Log.capture.error("visit not recorded: \(error.localizedDescription)")
        }
        applyPresence()
        scheduleTick(.visit, after: 0.5)
    }

    /// Presence updates and significant changes both land here. Either means the phone moved.
    private func moved(to location: CLLocation) {
        lastLocation = location
        // The launch tick covers the first update. After that, one movement tick per heartbeat interval is plenty.
        guard let lastTick, Date().timeIntervalSince(lastTick) >= Self.heartbeatInterval else { return }
        scheduleTick(.movement, after: 1)
    }
}

extension CaptureCoordinator: CLLocationManagerDelegate {
    // CoreLocation calls back on the thread that created the manager, which is the main thread here.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            locationStatus = status
            applyLocationServices()
            if status == .authorizedWhenInUse { self.manager.requestAlwaysAuthorization() }
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
        guard let last = locations.last else { return }
        MainActor.assumeIsolated { moved(to: last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Log.capture.error("location: \(error.localizedDescription)")
    }
}
