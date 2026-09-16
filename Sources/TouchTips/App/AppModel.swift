import Foundation
import Observation
import TouchTipsCore
import UIKit

/// The one object views reach for. Owns the database and the long-running workers.
@MainActor
@Observable
final class AppModel {
    let database: AppDatabase
    let capture: CaptureCoordinator
    let geocoder: Geocoder
    let notifier: Notifier
    let photos: ContactPhotos
    let contactsAccess = ContactsAccess()
    let locationAccess = LocationAccess()

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
        geocoder = Geocoder(database: database)
        capture.didIngest = { [geocoder, photos] in
            // Invalidate without fetching. A background scan may consume the only photo-change event.
            photos.reset()
            // Headless shortcut work must not start optional map work.
            guard UIApplication.shared.applicationState == .active else { return }
            geocoder.kick()
        }
    }

    func start() {
        notifier.activate()
        // The foreground scene establishes the first baseline. A cold App Intent
        // must not silently consume the contact it was asked to discover.
        capture.start(checkOnLaunch: false)
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
