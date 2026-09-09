import XCTest

@MainActor
final class AutoCaptureSettingsUITests: XCTestCase {
    func testHeadingsAndGlassDeleteConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingDone", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Preferences"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["People page"].exists)
        let top = XCTAttachment(screenshot: app.screenshot())
        top.name = "Settings preferences and access"
        top.lifetime = .keepAlways
        add(top)
        let delete = app.buttons["Delete all data"]
        for _ in 0 ..< 6 where !delete.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["Map page"].exists)
        XCTAssertTrue(delete.isHittable)
        XCTAssertEqual(delete.frame.midX, app.frame.midX, accuracy: 2)
        let bottom = XCTAttachment(screenshot: app.screenshot())
        bottom.name = "Settings map and glass delete"
        bottom.lifetime = .keepAlways
        add(bottom)
        delete.tap()
        let alert = app.alerts["Delete everything TouchTips knows?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Cancel"].tap()
        XCTAssertFalse(alert.exists)
    }

    func testGrantedAccessRowsOpenSystemSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingDone", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        for permission in ["contacts", "location"] {
            let row = app.buttons["settings-access-\(permission)"]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
            XCTAssertTrue(XCUIApplication(bundleIdentifier: "com.apple.Preferences")
                .wait(for: .runningForeground, timeout: 5))
            app.activate()
            XCTAssertTrue(row.waitForExistence(timeout: 5))
        }
    }

    func testToggleAboveAccessPersistsAcrossRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingDone", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        let toggle = app.switches["Auto-capture location"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertLessThan(toggle.frame.maxY, app.buttons["settings-access-contacts"].frame.minY)
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
