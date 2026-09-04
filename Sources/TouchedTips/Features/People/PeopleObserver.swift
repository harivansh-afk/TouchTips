import Contacts
import Observation
import SwiftUI
import TouchedTipsCore

/// Every person with their answer, kept current from the database, already grouped for the list.
/// Grouping happens here once per emission, never in a view body.
@MainActor
@Observable
final class PeopleObserver {
    /// Why the list might be empty.
    enum Readiness {
        /// Contacts access was not granted, so nothing can be noticed.
        case contactsOff
        /// Access is granted and the first read of the contact store has not finished.
        case reading
        case ready
    }

    private(set) var rows: [PersonRow] = []
    private(set) var sections: [PeopleSection] = []
    private(set) var undocumented: [PersonRow] = []
    /// The same dated people by place, and as one line, for the layouts Settings can choose.
    private(set) var placeSections: [PeopleSection] = []
    private(set) var timeline: [TimelineItem] = []
    private(set) var readiness: Readiness = .reading

    func run(in database: AppDatabase) async {
        let observation = ValueObservation.tracking { db in
            (rows: try Person.rows().fetchAll(db), hasReadContacts: try db.value(for: .contactsHistoryToken) != nil)
        }
        do {
            for try await value in observation.values(in: database.reader) {
                if rows != value.rows {
                    rows = value.rows
                    let groups = PeopleSections.make(from: value.rows)
                    if sections != groups.sections { sections = groups.sections }
                    if undocumented != groups.undocumented { undocumented = groups.undocumented }
                    let places = PeopleSections.byPlace(from: value.rows)
                    if placeSections != places { placeSections = places }
                    let line = PeopleSections.timeline(from: groups.sections)
                    if timeline != line { timeline = line }
                }
                let next = Self.readiness(rowsEmpty: value.rows.isEmpty, hasReadContacts: value.hasReadContacts)
                if readiness != next { readiness = next }
            }
        } catch is CancellationError {
            // The view went away. Not an error.
        } catch {
            Log.ui.error("people observation ended: \(error.localizedDescription)")
        }
    }

    private static func readiness(rowsEmpty: Bool, hasReadContacts: Bool) -> Readiness {
        guard rowsEmpty else { return .ready }
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return .contactsOff }
        return hasReadContacts ? .ready : .reading
    }
}
