import AppIntents

/// An execution opportunity, not evidence that a contact was just saved or a meeting occurred.
struct CheckContactsIntent: AppIntent {
    static let title: LocalizedStringResource = "Check for new contacts"
    static let description = IntentDescription(
        "Check Contacts for additions and send TouchTips notifications. Set up Contacts access in TouchTips first. Does not use background location."
    )
    static var supportedModes: IntentModes {
        .background
    }

    /// This permits invocation while locked, but never bypasses Contacts or file protection.
    static var authenticationPolicy: IntentAuthenticationPolicy {
        .alwaysAllowed
    }

    func perform() async throws -> some IntentResult {
        try await AppRuntime.checkContacts()
        return .result()
    }
}

struct TouchTipsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckContactsIntent(),
            phrases: ["Check for new contacts in \(.applicationName)"],
            shortTitle: "Check new contacts",
            systemImageName: "person.crop.circle.badge.plus"
        )
    }
}
