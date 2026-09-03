import Contacts
import CoreLocation
import Observation
import TouchedTipsCore
import UIKit

/// Wakes on visits and contact changes, diffs the contact store, and hands both to `Ingest`.
@MainActor
@Observable
final class CaptureCoordinator: NSObject {
    private let database: AppDatabase
    private let manager = CLLocationManager()
    private var tickTask: Task<Void, Never>?
    private var contactsObserver: (any NSObjectProtocol)?

    private(set) var locationStatus: CLAuthorizationStatus
    private(set) var lastTick: Date?
    /// The visit we are in right now, if CoreLocation has told us about it.
    private(set) var currentVisit: Visit?
    /// Fires after anything landed in the database.
    var didIngest: (() -> Void)?

    var locationGranted: Bool { locationStatus == .authorizedAlways }

    init(database: AppDatabase) {
        self.database = database
        locationStatus = manager.authorizationStatus
        super.init()
    }

    /// Call once at launch, every launch. Setting the delegate again is what lets CoreLocation
    /// deliver the visit that relaunched a terminated app.
    func start() {
        manager.delegate = self
        startVisitMonitoringIfAuthorized()
        contactsObserver = NotificationCenter.default.addObserver(
            forName: .CNContactStoreDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleTick() }
        }
        // Give a launch-time visit a moment to land so the add it explains gets a place on the first pass.
        scheduleTick(after: 2)
    }

    func requestLocation() {
        switch locationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    func scheduleTick(after delay: TimeInterval = 1) {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.tick()
        }
    }

    /// Diff the contact store and resolve anything new. Safe to call repeatedly.
    func tick() async {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return }
        let background = UIApplication.shared.beginBackgroundTask()
        defer { UIApplication.shared.endBackgroundTask(background) }

        let database = database
        do {
            let token = try await database.reader.read { db in try db.value(for: .contactsHistoryToken) }
            let changes = try await Task.detached(priority: .utility) { try ContactsDiff().changes(since: token) }.value
            let summary = try await Task.detached(priority: .utility) { try Ingest.apply(changes, now: .now, to: database) }.value
            lastTick = .now
            Log.capture.info(
                "tick: \(summary.newPeople) new, \(summary.snapshotted) snapshotted, \(summary.updated) updated, \(summary.deleted) deleted"
            )
            if summary != IngestSummary() { didIngest?() }
        } catch {
            Log.capture.error("tick failed: \(error.localizedDescription)")
        }
    }

    private func startVisitMonitoringIfAuthorized() {
        guard locationStatus == .authorizedAlways || locationStatus == .authorizedWhenInUse else { return }
        manager.startMonitoringVisits()
    }

    private func record(_ live: LiveVisit) {
        do {
            let visit = try Ingest.recordLiveVisit(live, now: .now, to: database)
            currentVisit = visit.isOngoing ? visit : nil
            didIngest?()
        } catch {
            Log.capture.error("visit not recorded: \(error.localizedDescription)")
        }
        scheduleTick(after: 0.5)
    }
}

extension CaptureCoordinator: CLLocationManagerDelegate {
    // CoreLocation calls back on the thread that created the manager, which is the main thread here.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            locationStatus = status
            startVisitMonitoringIfAuthorized()
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

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Log.capture.error("location: \(error.localizedDescription)")
    }
}
