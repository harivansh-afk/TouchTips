@testable import TouchTips
import TouchTipsCore
import XCTest

@MainActor
final class ShortcutRuntimeTests: XCTestCase {
    func testIntentAndAppDelegateShareOneRuntime() {
        XCTAssertTrue(AppDelegate().session === AppRuntime.session)
    }

    func testHeadlessStorageFailureIsReportedWithoutCreatingAnEmptyStore() async {
        var starts = 0
        let session = AppSession(open: { throw CocoaError(.fileReadNoPermission) }, start: { _ in starts += 1 })
        do {
            _ = try await AppRuntime.checkContacts(in: session)
            XCTFail("Storage failure must not become a successful shortcut check")
        } catch AppRuntime.RuntimeError.storageUnavailable {
            XCTAssertNil(session.app)
            XCTAssertEqual(starts, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAppBundleDoesNotDeclareBackgroundLocationOrAlwaysPermission() {
        let bundle = Bundle(for: AppDelegate.self)
        let modes = bundle.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        XCTAssertFalse(modes.contains("location"))
        XCTAssertNil(bundle.object(forInfoDictionaryKey: "NSLocationAlwaysAndWhenInUseUsageDescription"))
        XCTAssertNotNil(bundle.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription"))
    }
}
