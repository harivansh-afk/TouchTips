import Contacts
import Observation
import UIKit

/// Contact thumbnails, fetched once per contact and kept in memory. Contacts owns the photo;
/// this only reads it. A contact with no photo is remembered so the store is not asked again.
@MainActor
@Observable
final class ContactPhotos {
    struct LoadID: Hashable {
        let contactID: String
        let generation: Int
    }

    private var images: [String: UIImage] = [:]
    private var missing: Set<String> = []
    private var inFlight: Set<String> = []
    private var generation = 0
    private let fetch: @MainActor (String) async -> Data?

    init(fetch: @escaping @MainActor (String) async -> Data? = ContactPhotos.fetchThumbnail) {
        self.fetch = fetch
    }

    func loadID(for contactID: String) -> LoadID {
        LoadID(contactID: contactID, generation: generation)
    }

    func image(for contactID: String) -> UIImage? {
        images[contactID]
    }

    func load(_ contactID: String) async {
        guard images[contactID] == nil, !missing.contains(contactID), !inFlight.contains(contactID) else { return }
        let generation = generation
        inFlight.insert(contactID)
        let data = await fetch(contactID)
        guard generation == self.generation else { return }
        store(data.flatMap(UIImage.init(data:)), for: contactID)
    }

    /// Contacts changed. Drop everything so edited photos show on the next render.
    func reset() {
        generation += 1
        images.removeAll()
        missing.removeAll()
        inFlight.removeAll()
    }

    private func store(_ image: UIImage?, for contactID: String) {
        inFlight.remove(contactID)
        if let image {
            images[contactID] = image
        } else {
            missing.insert(contactID)
        }
    }

    private static func fetchThumbnail(_ contactID: String) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            let keys = [CNContactThumbnailImageDataKey as CNKeyDescriptor]
            return try? CNContactStore().unifiedContact(withIdentifier: contactID, keysToFetch: keys).thumbnailImageData
        }.value
    }
}
