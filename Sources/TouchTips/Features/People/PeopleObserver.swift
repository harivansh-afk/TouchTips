import Observation
import SwiftUI
import TouchTipsCore

/// Every person with their answer, kept current from the database. One per screen that lists people.
@MainActor
@Observable
final class PeopleObserver {
    private(set) var rows: [PersonRow] = []

    func run(in database: AppDatabase) async {
        let observation = ValueObservation.tracking { db in try Person.rows().fetchAll(db) }
        do {
            for try await value in observation.values(in: database.reader) {
                if rows != value { rows = value }
            }
        } catch is CancellationError {
            // The view went away. Not an error.
        } catch {
            Log.ui.error("people observation ended: \(error.localizedDescription)")
        }
    }
}
