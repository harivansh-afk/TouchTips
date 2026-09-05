import Foundation
import GRDB

/// Saved in the same transaction as the contact and history token. Removed after notification submission.
public struct PendingNotice: Codable, FetchableRecord, PersistableRecord, Sendable {
    public var contactID: String
    public var createdAt: Date

    public init(contactID: String, createdAt: Date) {
        self.contactID = contactID
        self.createdAt = createdAt
    }

    public static func all() -> QueryInterfaceRequest<PendingNotice> {
        order(Column("createdAt"), Column("contactID"))
    }
}
