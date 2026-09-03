import Foundation
import Observation
import TouchTipsCore

/// The one object views reach for. Owns the database and the two long-running workers.
@MainActor
@Observable
final class AppModel {
    let database: AppDatabase
    let capture: CaptureCoordinator
    let geocoder: Geocoder
    let contactsAccess = ContactsAccess()

    init() {
        database = AppModel.openDatabase()
        capture = CaptureCoordinator(database: database)
        geocoder = Geocoder(database: database)
        capture.didIngest = { [geocoder] in geocoder.kick() }
    }

    func start() {
        capture.start()
        geocoder.kick()
    }

    private static func openDatabase() -> AppDatabase {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            return try AppDatabase.onDisk(in: support.appendingPathComponent("Database", isDirectory: true))
        } catch {
            Log.database.fault("Could not open the database, running in memory: \(error.localizedDescription)")
            // In-memory SQLite cannot fail short of the library being missing, which would be a broken OS.
            return try! AppDatabase.inMemory()
        }
    }
}
