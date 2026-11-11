import CoreLocation
import TouchTipsCore
import UIKit

/// The one automatic use of location. A contact that appeared in the last `window` was most likely
/// saved where the phone is now, so when the app is open that place is offered as a suggestion for
/// the user to confirm. Nothing runs in the background: iOS gives a while-in-use app no location there.
@MainActor
final class PlaceOnOpen {
    /// Long enough to cover saving a contact and opening the app from its notification; short enough
    /// that the user has rarely left the place.
    static let window: TimeInterval = 20 * 60

    private let database: AppDatabase
    private let location: LocationAccess
    private let isActive: () -> Bool
    private var running: Task<Void, Never>?
    private var again = false

    init(
        database: AppDatabase, location: LocationAccess,
        isActive: @escaping () -> Bool = { UIApplication.shared.applicationState == .active }
    ) {
        self.database = database
        self.location = location
        self.isActive = isActive
    }

    /// Fill in recent contacts' place. Concurrent calls share one pass, and a call that lands mid-pass
    /// runs one more, so a contact found meanwhile is not missed.
    func fill() async {
        if let running {
            again = true
            await running.value
            return
        }
        let work = Task {
            repeat {
                again = false
                await pass()
            } while again
        }
        running = work
        await work.value
        running = nil
    }

    /// `fill`, but give up waiting after `limit`. The pass itself still finishes.
    func fill(within limit: Duration) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fill() }
            group.addTask { try? await Task.sleep(for: limit) }
            await group.next()
            group.cancelAll()
        }
    }

    private func pass() async {
        guard location.usable, isActive() else { return }
        let cutoff = Date(timeIntervalSinceNow: -Self.window)
        let waiting: Int
        do {
            waiting = try await database.reader.read { db in try Meet.awaitingPlace(seenSince: cutoff).fetchCount(db) }
        } catch {
            Log.capture.error("place on open: read failed: \(error.localizedDescription)")
            return
        }
        guard waiting > 0 else { return }
        guard let fix = await location.fix() else {
            Log.capture.notice("place on open: no precise fix")
            return
        }
        guard let here = await PlaceSearch.here(fix) else {
            Log.capture.notice("place on open: nothing named here")
            return
        }
        let place = Place(key: here.key, latitude: here.latitude, longitude: here.longitude, name: here.name)
        do {
            // The window is measured from the fix: that is the moment the phone was known to be here.
            let filled = try Ingest.suggestPlace(
                place, forContactsSeenSince: fix.timestamp.addingTimeInterval(-Self.window), now: .now, to: database
            )
            Log.capture.notice("place on open: suggested for \(filled.count, privacy: .public)")
        } catch {
            Log.capture.error("place on open: write failed: \(error.localizedDescription)")
        }
    }
}
