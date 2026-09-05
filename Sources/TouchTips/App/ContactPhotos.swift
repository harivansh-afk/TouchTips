import Contacts
import Observation
import UIKit

/// Contact thumbnails, fetched once per contact and kept in memory. Contacts owns the photo;
/// this only reads it. A contact with no photo is remembered so the store is not asked again.
@MainActor
@Observable
final class ContactPhotos {
    private var images: [String: UIImage] = [:]
    private var missing: Set<String> = []
    private var inFlight: Set<String> = []

    func image(for contactID: String) -> UIImage? {
        images[contactID]
    }

    func load(_ contactID: String) {
        guard images[contactID] == nil, !missing.contains(contactID), !inFlight.contains(contactID) else { return }
        inFlight.insert(contactID)
        Task.detached(priority: .userInitiated) {
            let keys = [CNContactThumbnailImageDataKey as CNKeyDescriptor]
            let data = try? CNContactStore().unifiedContact(withIdentifier: contactID, keysToFetch: keys).thumbnailImageData
            let image = data.flatMap(UIImage.init(data:))
            await MainActor.run { self.store(image, for: contactID) }
        }
    }

    /// Contacts changed. Drop everything so edited photos show on the next render.
    func reset() {
        images.removeAll()
        missing.removeAll()
    }

    private func store(_ image: UIImage?, for contactID: String) {
        inFlight.remove(contactID)
        if let image {
            images[contactID] = image
        } else {
            missing.insert(contactID)
        }
    }
}
