import XCTest

@MainActor
final class AutoCaptureSettingsUITests: XCTestCase {
    func testToggleAboveAccessPersistsAcrossRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingDone", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        let toggle = app.switches["Auto-capture location"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertLessThan(toggle.frame.maxY, app.staticTexts["Contacts"].frame.minY)
        if toggle.value as? String == "0" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, "1")
        let enabledScreenshot = XCTAttachment(screenshot: app.screenshot())
        enabledScreenshot.name = "Auto-capture location on"
        enabledScreenshot.lifetime = .keepAlways
        add(enabledScreenshot)
        if toggle.value as? String == "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, "0")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Auto-capture location off"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
    }
}
