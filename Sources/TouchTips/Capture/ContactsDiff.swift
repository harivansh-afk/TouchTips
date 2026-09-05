import Contacts
import TouchTipsCore

/// Reads the contact store's change history since a token and flattens it for `Ingest`.
actor ContactsDiff {
    private let store = CNContactStore()

    func changes(since token: Data?) throws -> ContactChangeSet {
        let request = CNChangeHistoryFetchRequest()
        request.startingToken = token
        request.shouldUnifyResults = true
        request.additionalContactKeyDescriptors = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactOrganizationNameKey as CNKeyDescriptor,
        ]

        var error: NSError?
        guard let result = TTChangeHistoryEnumerator(store, request, &error)
        else { throw error ?? CNError(.communicationError) }

        var changes = ContactChangeSet(token: result.currentHistoryToken)
        for case let event as CNChangeHistoryEvent in result.value {
            switch event {
            case is CNChangeHistoryDropEverythingEvent:
                changes = ContactChangeSet(token: result.currentHistoryToken, isSnapshot: true)
            case let add as CNChangeHistoryAddContactEvent:
                changes.deletedIDs.removeAll { $0 == add.contact.identifier }
                changes.added.removeAll { $0.contactID == add.contact.identifier }
                changes.updated.removeAll { $0.contactID == add.contact.identifier }
                changes.added.append(snapshot(add.contact))
            case let update as CNChangeHistoryUpdateContactEvent:
                if let index = changes.added.firstIndex(where: { $0.contactID == update.contact.identifier }) {
                    changes.added[index] = snapshot(update.contact)
                } else {
                    changes.updated.removeAll { $0.contactID == update.contact.identifier }
                    changes.updated.append(snapshot(update.contact))
                }
            case let delete as CNChangeHistoryDeleteContactEvent:
                changes.added.removeAll { $0.contactID == delete.contactIdentifier }
                changes.updated.removeAll { $0.contactID == delete.contactIdentifier }
                changes.deletedIDs.append(delete.contactIdentifier)
            default:
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
