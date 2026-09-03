import Contacts
import ContactsUI
import SwiftUI

/// The system contact card, as a sheet. The one UIKit bridge in the app.
struct ContactCard: UIViewControllerRepresentable {
    let contactID: String

    func makeUIViewController(context: Context) -> UINavigationController {
        let navigation = UINavigationController()
        let store = CNContactStore()
        let keys = [CNContactViewController.descriptorForRequiredKeys()]
        if let contact = try? store.unifiedContact(withIdentifier: contactID, keysToFetch: keys) {
            let card = CNContactViewController(for: contact)
            card.contactStore = store
            card.allowsEditing = true
            navigation.viewControllers = [card]
        }
        return navigation
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}
