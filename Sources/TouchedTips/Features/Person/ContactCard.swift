import Contacts
import ContactsUI
import SwiftUI

/// The system contact card, as a sheet. The one UIKit bridge in the app. The card ships no bar
/// items of its own when presented, so a close item is added here and wired to `dismiss`.
struct ContactCard: UIViewControllerRepresentable {
    let contactID: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let navigation = UINavigationController()
        let store = CNContactStore()
        let keys = [CNContactViewController.descriptorForRequiredKeys()]
        if let contact = try? store.unifiedContact(withIdentifier: contactID, keysToFetch: keys) {
            let card = CNContactViewController(for: contact)
            card.contactStore = store
            card.allowsEditing = true
            card.navigationItem.leftBarButtonItem = UIBarButtonItem(
                systemItem: .close, primaryAction: UIAction { [coordinator = context.coordinator] _ in coordinator.close() }
            )
            navigation.viewControllers = [card]
        }
        return navigation
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    @MainActor final class Coordinator {
        private let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func close() {
            HapticManager.light()
            dismiss()
        }
    }
}
