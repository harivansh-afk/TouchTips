import Contacts
import TouchTipsCore

/// Reads the contact store's change history since a token and flattens it for `Ingest`.
struct ContactsDiff: Sendable {
    func changes(since token: Data?) throws -> ContactChangeSet {
        let store = CNContactStore()
        let request = CNChangeHistoryFetchRequest()
        request.startingToken = token
        request.shouldUnifyResults = true
        request.additionalContactKeyDescriptors = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]

        var error: NSError?
        let result = store.enumeratorForChangeHistoryFetchRequest(request, error: &error)
        if let error { throw error }

        var changes = ContactChangeSet(token: result.currentHistoryToken ?? store.currentHistoryToken ?? Data())
        for case let event as CNChangeHistoryEvent in result.value {
            switch event {
            case let add as CNChangeHistoryAddContactEvent:
                changes.added.append(snapshot(add.contact))
            case let update as CNChangeHistoryUpdateContactEvent:
                changes.updated.append(snapshot(update.contact))
            case let delete as CNChangeHistoryDeleteContactEvent:
                changes.deletedIDs.append(delete.contactIdentifier)
            default:
                // Drop-everything arrives on the first fetch and after a history reset.
                // Ingest handles both by only inserting people it has not seen.
                break
            }
        }
        return changes
    }

    private func snapshot(_ contact: CNContact) -> ContactSnapshot {
        let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        return ContactSnapshot(contactID: contact.identifier, name: name.isEmpty ? contact.organizationName : name)
    }
}
