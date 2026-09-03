import Contacts
import Observation

@MainActor
@Observable
final class ContactsAccess {
    private(set) var status = CNContactStore.authorizationStatus(for: .contacts)

    /// Limited access cannot see change history, so only full access counts.
    var granted: Bool { status == .authorized }

    func refresh() {
        status = CNContactStore.authorizationStatus(for: .contacts)
    }

    func request() async {
        _ = try? await CNContactStore().requestAccess(for: .contacts)
        refresh()
    }
}
