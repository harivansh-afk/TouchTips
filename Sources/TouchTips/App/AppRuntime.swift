import Foundation

/// One process-wide runtime for both system-invoked intents and the app delegate.
/// Never create a second cursor owner or substitute an empty database after an open failure.
@MainActor
enum AppRuntime {
    static let session = AppSession(start: { app in
        #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                return
            }
            NotificationTestFixture.prepare(app)
        #endif
        app.start()
    })

    @discardableResult
    static func checkContacts(in session: AppSession = session) async throws -> ContactCheckResult {
        try Task.checkCancellation()
        session.retry()
        guard let app = session.app else { throw RuntimeError.storageUnavailable }
        return try await app.capture.checkForNewContacts()
    }

    enum RuntimeError: LocalizedError {
        case storageUnavailable

        var errorDescription: String? {
            "TouchTips could not open saved data. Unlock your iPhone and open TouchTips, then try again."
        }
    }
}
