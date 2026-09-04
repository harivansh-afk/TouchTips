import AppIntents

/// Runs a tick without opening the app. Meant for a Shortcuts automation on Contacts or Messages closing.
struct CheckForNewPeopleIntent: AppIntent {
    static let title: LocalizedStringResource = "Check for new people"
    static let description = IntentDescription("Looks for contacts added since the last check.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await AppModel.shared?.capture.tick(.intent)
        return .result()
    }
}

/// Marks where the phone is. The next new contact gets this place. Meant for the Action Button.
struct JustMetIntent: AppIntent {
    static let title: LocalizedStringResource = "I just met someone"
    static let description = IntentDescription("Marks where you are, so the next new contact gets this place.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let marked = await AppModel.shared?.capture.witness() ?? false
        return .result(dialog: marked ? "Marked." : "No location.")
    }
}

struct TouchedTipsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckForNewPeopleIntent(),
            phrases: ["Check for new people in \(.applicationName)"],
            shortTitle: "Check for new people",
            systemImageName: "person.crop.circle.badge.plus"
        )
        AppShortcut(
            intent: JustMetIntent(),
            phrases: ["I just met someone in \(.applicationName)"],
            shortTitle: "Just met",
            systemImageName: "mappin"
        )
    }
}
