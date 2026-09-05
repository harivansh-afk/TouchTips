import Foundation
import Observation
import TouchTipsCore

/// Editing and capture are available only after the persistent store opens successfully.
@MainActor
@Observable
final class AppSession {
    private(set) var app: AppModel?
    private let open: @MainActor () throws -> AppDatabase
    private let start: @MainActor (AppModel) -> Void

    init(
        open: @escaping @MainActor () throws -> AppDatabase = { try AppModel.openDatabase() },
        start: @escaping @MainActor (AppModel) -> Void = { $0.start() }
    ) {
        self.open = open
        self.start = start
    }

    func retry() {
        guard app == nil else { return }
        do {
            let opened = try AppModel(database: open())
            app = opened
            start(opened)
        } catch {
            Log.database.fault("Could not open saved data: \(error.localizedDescription)")
        }
    }
}
