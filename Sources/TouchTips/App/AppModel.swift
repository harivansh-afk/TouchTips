import Foundation
import Observation
import TouchTipsCore

/// The one object views reach for. Owns the database and the long-running workers.
@MainActor
@Observable
final class AppModel {
    let database: AppDatabase
    let capture: CaptureCoordinator
    let notifier: Notifier
    let photos: ContactPhotos
    let cloud: CloudSync
    let contactsAccess = ContactsAccess()

    /// The app's own database in Application Support.
    convenience init() throws {
        try self.init(database: AppModel.openDatabase())
    }

    /// Any database. Previews and tests hand in an in-memory one; nothing starts until `start()`.
    init(database: AppDatabase, photos: ContactPhotos = ContactPhotos()) {
        self.database = database
        self.photos = photos
        notifier = Notifier(database: database)
        capture = CaptureCoordinator(database: database, notifier: notifier)
        cloud = CloudSync(database: database)
        capture.didIngest = { [photos] in photos.reset() }
        notifier.onApproval = { [cloud] id, allow in
            if let allow {
                await cloud.decide(id, allow: allow)
            } else {
                await cloud.checkApprovals(showing: id)
            }
        }
    }

    func start() {
        notifier.activate()
        capture.start()
        cloud.start()
    }

    static func openDatabase() throws -> AppDatabase {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        #if DEBUG && targetEnvironment(simulator)
            if let database = try QATestFixture.database(in: support) {
                return database
            }
            if let session = NotificationTestFixture.session {
                return try AppDatabase.onDisk(in: support.appendingPathComponent(
                    "NotificationTests/\(session)",
                    isDirectory: true
                ))
            }
        #endif
        return try AppDatabase.onDisk(in: support.appendingPathComponent("Database", isDirectory: true))
    }
}
