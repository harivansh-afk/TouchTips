import XCTest

/// The screens location touches. Needs a simulator with location granted While Using and set
/// somewhere with places around it; CI does both with `simctl` before running these.
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
        return app
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
