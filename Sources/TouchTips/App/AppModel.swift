import Foundation
import Observation
import TouchTipsCore

/// The one object views reach for. Owns the database and the long-running workers.
@MainActor
@Observable
final class AppModel {
    let database: AppDatabase
    let capture: CaptureCoordinator
    let geocoder: Geocoder
    let notifier: Notifier
    let photos = ContactPhotos()
    let contactsAccess = ContactsAccess()

    /// The app's own database in Application Support.
    convenience init() {
        self.init(database: AppModel.openDatabase())
    }

    /// Any database. Previews and tests hand in an in-memory one; nothing starts until `start()`.
    init(database: AppDatabase) {
        self.database = database
        notifier = Notifier(database: database)
        capture = CaptureCoordinator(database: database, notifier: notifier)
        geocoder = Geocoder(database: database)
        capture.didIngest = { [geocoder, photos] in
            geocoder.kick()
            photos.reset()
        }
    }

    func start() {
        notifier.activate()
        capture.start()
        geocoder.kick()
    }

    private static func openDatabase() -> AppDatabase {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            #if DEBUG && targetEnvironment(simulator)
                if let database = try QATestFixture.database(in: support) { return database }
                if let session = NotificationTestFixture.session {
                    return try AppDatabase.onDisk(in: support.appendingPathComponent(
                        "NotificationTests/\(session)",
                        isDirectory: true
                    ))
                }
            #endif
            return try AppDatabase.onDisk(in: support.appendingPathComponent("Database", isDirectory: true))
        } catch {
            Log.database.fault("Could not open the database, running in memory: \(error.localizedDescription)")
            // In-memory SQLite cannot fail short of the library being missing, which would be a broken OS.
            return try! AppDatabase.inMemory()
        }
    }
}
