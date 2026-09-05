import XCTest

@MainActor
final class TabBarUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testOnlyCustomBarAcrossTabsPushesSheetsAndRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingDone", "YES"]
        app.launchEnvironment["TOUCHTIPS_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["TOUCHTIPS_TEST_PERSON"] = "tab-bar-person"
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.buttons["Allow"].waitForExistence(timeout: 3) {
            springboard.alerts.buttons["Allow"].tap()
        }
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        assertSingleBar(app, screen: "cold-people")

        app.buttons["Map"].tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 10))
        assertSingleBar(app, screen: "map")
        app.buttons["People"].tap()
        assertSingleBar(app, screen: "returned-people")

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        assertSingleBar(app, screen: "dismissed-settings")

        let person = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Notification Test Person"))
            .firstMatch
        XCTAssertTrue(person.waitForExistence(timeout: 5))
        person.tap()
        XCTAssertTrue(app.staticTexts["person-name"].waitForExistence(timeout: 5))
        assertSingleBar(app, screen: "people-detail", back: true)
        app.swipeUp()
        assertSingleBar(app, screen: "scrolled-detail", back: true)
        app.buttons["Back"].tap()
        assertSingleBar(app, screen: "popped-people")

        app.buttons["Search"].tap()
        let search = app.textFields["Name, place or note"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        assertSingleBar(app, screen: "search")
        search.tap()
        search.typeText("Notification Test Person")
        XCTAssertTrue(person.waitForExistence(timeout: 5))
        person.tap()
        XCTAssertTrue(app.staticTexts["person-name"].waitForExistence(timeout: 5))
        assertSingleBar(app, screen: "search-detail", back: true)
        app.buttons["Back"].tap()
        assertSingleBar(app, screen: "popped-search")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        assertSingleBar(app, screen: "relaunched-people")
    }

    private func assertSingleBar(_ app: XCUIApplication, screen: String, back: Bool = false) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "single-bar-\(screen)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertFalse(
            app.tabBars.firstMatch.exists,
            "The system tab bar must not render below the custom bar: \(screen)"
        )
        for name in ["People", "Map", "Search"] {
            XCTAssertEqual(app.buttons.matching(identifier: name).count, 1, "Duplicate custom control: \(name)")
        }
        XCTAssertEqual(app.buttons.matching(identifier: "Back").count, back ? 1 : 0)
    }
}
