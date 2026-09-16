import Foundation

/// A successful Contacts scan and outbox delivery attempt, not proof of a displayed notification.
struct ContactCheckResult: Sendable {
    let checkedAt: Date
}

enum ContactCheckError: Error, LocalizedError, Sendable, Equatable {
    case contactsAccessRequired
    case setupRequired
    case scanFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .contactsAccessRequired:
            "Allow full Contacts access for TouchTips in Settings, then try again."
        case .setupRequired:
            "Open TouchTips and finish setup before checking for new contacts from Shortcuts."
        case .scanFailed:
            "TouchTips could not finish checking Contacts. Open the app and try again."
        case .cancelled:
            "The contact check was cancelled. Try running the shortcut again."
        }
    }
}
