import Contacts
import Foundation
import PhoneNumberKit
import TouchTipsCore

/// One Add form's save operation. Contacts and SQLite cannot share a transaction, so retain the
/// saved identity and original time when the local write fails. Retrying updates the same contact.
@MainActor
final class ContactCreation {
    private let contact = CNMutableContact()
    private var savedAt: Date?
    private let saveContact: @MainActor (CNMutableContact, Bool) throws -> Void

    init(saveContact: @escaping @MainActor (CNMutableContact, Bool) throws -> Void = ContactCreation.saveContact) {
        self.saveContact = saveContact
    }

    func save(name: String, phone: String, place: Place?, at now: Date = .now, to database: AppDatabase) throws {
        let parts = name.split(separator: " ", maxSplits: 1)
        contact.givenName = parts.first.map(String.init) ?? ""
        contact.familyName = parts.count > 1 ? String(parts[1]) : ""
        let typed = phone.trimmingCharacters(in: .whitespaces)
        contact.phoneNumbers = []
        if !typed.isEmpty {
            let utility = PhoneNumberUtility()
            let stored = (try? utility.parse(typed)).map { utility.format($0, toType: .e164) } ?? typed
            contact.phoneNumbers = [CNLabeledValue(
                label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: stored)
            )]
        }
        try saveContact(contact, savedAt != nil)
        savedAt = savedAt ?? now
        try Ingest.addExact(
            contactID: contact.identifier, name: name, at: savedAt ?? now, place: place, to: database
        )
    }

    private static func saveContact(_ contact: CNMutableContact, updating: Bool) throws {
        let request = CNSaveRequest()
        if updating {
            request.update(contact)
        } else {
            request.add(contact, toContainerWithIdentifier: nil)
        }
        try CNContactStore().execute(request)
    }
}
