import Foundation
import Observation
import TouchedTipsCore

/// The one object views reach for. Owns the database and the two long-running workers.
@MainActor
@Observable
final class AppModel {
    let database: AppDatabase
    let capture: CaptureCoordinator
    let geocoder: Geocoder
    let photos = ContactPhotos()
    let contactsAccess = ContactsAccess()

    /// The app's own database in Application Support.
    convenience init() {
        self.init(database: AppModel.openDatabase())
    }

    /// Any database. Previews and tests hand in an in-memory one; nothing starts until `start()`.
    init(database: AppDatabase) {
        self.database = database
        capture = CaptureCoordinator(database: database)
        geocoder = Geocoder(database: database)
        capture.didIngest = { [geocoder, photos] in
            geocoder.kick()
            photos.reset()
        }
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
