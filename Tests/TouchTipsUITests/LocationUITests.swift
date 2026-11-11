import XCTest

/// The screens location touches. Needs a simulator set somewhere with places around it; CI sets it
/// with `simctl location`. Permission is given the way a person gives it, through the system prompt.
@MainActor
final class LocationUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(justMet: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingDone", "YES"]
        app.launchEnvironment["TOUCHTIPS_QA_SESSION"] = UUID().uuidString
        app.launchEnvironment["TOUCHTIPS_QA_DATA"] = "standard"
        if justMet {
            app.launchEnvironment["TOUCHTIPS_QA_JUST_MET"] = "1"
        }
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15))
        allowLocation(in: app)
        return app
    }

    /// From Settings: Allow, then the system prompt's While Using. Already allowed, it only checks.
    private func allowLocation(in app: XCUIApplication) {
        app.buttons["Settings"].tap()
        let row = app.buttons["settings-access-location"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        if row.label.contains("Allow") {
            row.tap()
            let prompt = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
            XCTAssertTrue(prompt.waitForExistence(timeout: 10), "Allow should show the system prompt")
            capture(app, "location-prompt")
            prompt.buttons["Allow While Using App"].tap()
        }
        let allowed = NSPredicate(format: "label CONTAINS %@", "While using")
        XCTAssertTrue(
            XCTWaiter().wait(for: [expectation(for: allowed, evaluatedWith: row)], timeout: 10) == .completed,
            row.label
        )
        app.buttons["Done"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// The map preview is labelled with the chosen place, or "Map preview" with none.
    private func waitForPlace(on map: XCUIElement, timeout: TimeInterval = 25) -> String? {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if map.exists, map.label != "Map preview", !map.label.isEmpty {
                return map.label
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nil
    }

    func testSettingsShowsLocationAccess() {
        let app = launch()
        app.buttons["Settings"].tap()
        let row = app.buttons["settings-access-location"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable)
        XCTAssertTrue(row.label.contains("While using"), row.label)
        capture(app, "settings-location")
    }

    func testAddSheetChoosesTheNearestPlace() {
        let app = launch()
        app.pullToAdd()
        XCTAssertTrue(app.textFields["Name"].waitForExistence(timeout: 5))
        // The simulator's first keyboard explains swipe typing over the sheet.
        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 2) {
            tip.tap()
        }
        let map = app.buttons["meeting.map"].exists ? app.buttons["meeting.map"] : app.otherElements["meeting.map"]
        let place = waitForPlace(on: map)
        capture(app, "add-sheet-nearby")
        XCTAssertNotNil(place, "The nearest place should be chosen")
        XCTAssertFalse(app.buttons["Near me"].exists, "Near me is only for asking permission")
    }

    func testAContactJustFoundGetsThePlaceOnOpen() {
        let app = launch(justMet: true)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "QA Newcomer")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        // A fix and a place lookup, then the row redraws with the place under the name.
        Thread.sleep(forTimeInterval: 8)
        capture(app, "people-just-met")
        row.tap()
        XCTAssertTrue(app.staticTexts["person-name"].waitForExistence(timeout: 5))
        let map = app.buttons["meeting.map"].exists ? app.buttons["meeting.map"] : app.otherElements["meeting.map"]
        let place = waitForPlace(on: map, timeout: 10)
        capture(app, "person-just-met")
        XCTAssertNotNil(place, "A contact found minutes ago should be given the place the phone is in")
        XCTAssertTrue(app.buttons["Near me"].exists == false)
    }
}
