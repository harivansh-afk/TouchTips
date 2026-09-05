import XCTest

@MainActor
final class RegularUseUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(data: String = "standard", onboarding: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingDone", onboarding ? "YES" : "NO", "-peopleLayout", "default"]
        app.launchEnvironment["TOUCHTIPS_QA_SESSION"] = UUID().uuidString
        app.launchEnvironment["TOUCHTIPS_QA_DATA"] = data
        app.launch()
        if onboarding {
            XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15))
        }
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(name)-accessibility"
        tree.lifetime = .keepAlways
        add(tree)
    }

    private func person(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
    }

    func testColdMapThenWarmMap() {
        let app = launch()
        capture(app, "cold-people")
        let coldStart = Date.now
        app.buttons["Map"].tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 15))
        let cold = Date.now.timeIntervalSince(coldStart)
        capture(app, "cold-map-first-accessible-frame")
        // Rendered tiles need visual inspection; an accessible Map alone is not tile readiness.
        Thread.sleep(forTimeInterval: 3)
        capture(app, "cold-map-after-three-seconds")
        app.buttons["People"].tap()
        let warmStart = Date.now
        app.buttons["Map"].tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 5))
        let warm = Date.now.timeIntervalSince(warmStart)
        let timings =
            XCTAttachment(
                string: "Map tap to accessible map (includes XCTest interaction): cold=\(cold)s warm=\(warm)s. Not a tile-render metric."
            )
        timings.name = "map-interaction-timing"
        timings.lifetime = .keepAlways
        add(timings)
        capture(app, "warm-map")
    }

    func testSearchFromPersonReturnsToSearch() {
        let app = launch()
        app.buttons["Search"].tap()
        let field = app.textFields["Name, place or note"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("QA Alice")
        let alice = person("QA Alice", in: app)
        XCTAssertTrue(alice.waitForExistence(timeout: 5))
        alice.tap()
        XCTAssertTrue(app.staticTexts["person-name"].waitForExistence(timeout: 5))
        app.buttons["Search"].tap()
        capture(app, "search-reselected-from-person")
        XCTAssertTrue(app.staticTexts["person-name"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(field.isHittable)
    }

    func testPlaceLinkReturnsToMapFromMapPerson() {
        let app = launch()
        person("QA Alice", in: app).tap()
        XCTAssertTrue(app.buttons["QA Coffee"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["QA Coffee"].firstMatch.tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 10))
        let pin = app.buttons["QA Alice"]
        XCTAssertTrue(pin.waitForExistence(timeout: 10), app.debugDescription)
        pin.tap()
        XCTAssertTrue(app.staticTexts["person-name"].waitForExistence(timeout: 5))
        app.buttons["QA Coffee"].firstMatch.tap()
        capture(app, "place-link-from-map-person")
        XCTAssertTrue(app.staticTexts["person-name"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.maps.firstMatch.isHittable)
    }

    func testNotePersistsAfterNavigationAndRelaunch() {
        let app = launch()
        person("QA Alice", in: app).tap()
        XCTAssertTrue(app.staticTexts["person-name"].waitForExistence(timeout: 5))
        app.swipeUp()
        let note = app.textFields["Anything worth remembering"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        note.typeText("QA note persisted")
        app.buttons["Back"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        person("QA Alice", in: app).tap()
        XCTAssertTrue(app.staticTexts["person-name"].waitForExistence(timeout: 5))
        app.swipeUp()
        let saved = app.textFields.matching(NSPredicate(format: "value == %@", "QA note persisted")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
    }

    func testOnboardingContentReachable() {
        let app = launch(data: "empty", onboarding: false)
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 15))
        // Permission rows are staged after the headline animation, but exist before they are visible.
        Thread.sleep(forTimeInterval: 6)
        capture(app, "onboarding-current-text-size")
        for title in ["Contacts", "Location, Always", "Notifications"] {
            let label = app.staticTexts[title]
            for _ in 0 ..< 8 where !label.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(label.isHittable, "Unreachable onboarding permission: \(title)")
            capture(app, "onboarding-\(title)")
        }
        if !app.buttons["Start"].isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["Start"].isHittable)
        app.buttons["Start"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
    }

    func testLargeLibrarySearchAndNoResults() {
        let app = launch(data: "large")
        app.buttons["Search"].tap()
        let field = app.textFields["Name, place or note"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("QA Person 0999")
        XCTAssertTrue(person("QA Person 0999", in: app).waitForExistence(timeout: 5))
        capture(app, "thousand-contact-search")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "QA Person 0999".count))
        field.typeText("No such QA person")
        capture(app, "no-results")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "No Results")).firstMatch
            .waitForExistence(timeout: 5))
    }

    func testAddCancelDoesNotCreatePerson() {
        let app = launch()
        app.buttons["Add"].tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        name.typeText("QA Cancelled Contact")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        app.buttons["Search"].tap()
        let field = app.textFields["Name, place or note"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("QA Cancelled Contact")
        XCTAssertFalse(person("QA Cancelled Contact", in: app).exists)
        capture(app, "cancelled-contact-no-results")
    }

    func testUndocumentedPersonCanExplicitlyChooseToday() {
        let app = launch()
        app.buttons["Search"].tap()
        let field = app.textFields["Name, place or note"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("QA Undocumented")
        person("QA Undocumented", in: app).tap()
        let today = app.buttons["meeting.useToday"]
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        today.tap()
        XCTAssertTrue(today.waitForNonExistence(timeout: 5))
        capture(app, "explicit-today")
    }

    func testSettingsLayoutsAndMapStyles() {
        let app = launch()
        for title in ["Timeline", "Location", "Default"] {
            app.buttons["Settings"].tap()
            let option = app.buttons[title].firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            option.tap()
            app.buttons["Done"].tap()
            XCTAssertTrue(person("QA Alice", in: app).waitForExistence(timeout: 5))
            capture(app, "people-layout-\(title)")
        }
        for title in ["Standard", "Satellite", "Hybrid", "Muted"] {
            app.buttons["Settings"].tap()
            let option = app.buttons[title].firstMatch
            for _ in 0 ..< 5 where !option.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(option.isHittable)
            option.tap()
            app.buttons["Done"].tap()
            app.buttons["Map"].tap()
            XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 5))
            capture(app, "map-style-\(title)")
            app.buttons["People"].tap()
        }
    }

    func testWhileUsingLocationOffersSettingsRecovery() {
        // The test runner grants When In Use through simctl before this test.
        let app = launch()
        app.buttons["Settings"].tap()
        capture(app, "location-permission-recovery")
        let recovery = app.buttons["Location, Open Settings"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 5))
        recovery.tap()
        XCTAssertTrue(XCUIApplication(bundleIdentifier: "com.apple.Preferences").wait(
            for: .runningForeground,
            timeout: 5
        ))
        app.activate()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    }

    func testStorageFailureBlocksEditingAndRetryRecovers() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingDone", "YES"]
        app.launchEnvironment["TOUCHTIPS_QA_SESSION"] = UUID().uuidString
        app.launchEnvironment["TOUCHTIPS_QA_STORAGE_FAILURE"] = "once"
        app.launch()
        XCTAssertTrue(app.buttons["storage.retry"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Add"].exists)
        capture(app, "storage-unavailable")
        app.buttons["storage.retry"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(person("QA Alice", in: app).waitForExistence(timeout: 5))
        capture(app, "storage-recovered")
    }
}
