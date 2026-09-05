import XCTest

@MainActor
final class PeopleScrollUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(layout: String = "default") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingDone", "YES", "-peopleLayout", layout]
        app.launchEnvironment["TOUCHTIPS_QA_SESSION"] = UUID().uuidString
        app.launchEnvironment["TOUCHTIPS_QA_DATA"] = "standard"
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15))
        return app
    }

    private func alice(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "QA Alice")).firstMatch
    }

    private func waitUntil(_ condition: @escaping () -> Bool) -> Bool {
        let predicate = NSPredicate { _, _ in condition() }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)],
            timeout: 5
        ) == .completed
    }

    private func scrollPastAlice(in app: XCUIApplication) {
        let firstRow = alice(in: app)
        app.swipeUp()
        XCTAssertTrue(waitUntil { !firstRow.exists || !firstRow.isHittable }, "Alice should leave the viewport before reselecting People")
        XCTAssertFalse(app.buttons["Settings"].isHittable, "Scrolling should hide the People header")
    }

    private func assertAtTop(_ app: XCUIApplication, originalY: CGFloat) {
        let firstRow = alice(in: app)
        XCTAssertTrue(waitUntil {
            firstRow.exists && firstRow.isHittable && abs(firstRow.frame.minY - originalY) <= 12
                && app.buttons["Settings"].isHittable && app.buttons["Add"].isHittable
        }, "Reselecting People should restore the first row's original position and the header")
        XCTAssertFalse(app.staticTexts["person-name"].exists, "A tab tap must not open a person")
    }

    private func assertRepeatedReselectScrollsToTop(layout: String) {
        let app = launch(layout: layout)
        let firstRow = alice(in: app)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        XCTAssertTrue(firstRow.isHittable)
        let originalY = firstRow.frame.minY

        // The second round catches implementations that only react to the first reselect.
        for _ in 0 ..< 2 {
            scrollPastAlice(in: app)
            app.buttons["People"].tap()
            assertAtTop(app, originalY: originalY)
        }
    }

    func testDefaultPeopleReselectRepeatedlyScrollsToTop() {
        assertRepeatedReselectScrollsToTop(layout: "default")
    }

    func testTimelinePeopleReselectRepeatedlyScrollsToTop() {
        assertRepeatedReselectScrollsToTop(layout: "timeline")
    }

    func testLocationPeopleReselectRepeatedlyScrollsToTop() {
        assertRepeatedReselectScrollsToTop(layout: "location")
    }

    func testSwitchingBackToPeoplePreservesScrollPosition() {
        let app = launch()
        XCTAssertTrue(alice(in: app).waitForExistence(timeout: 5))
        scrollPastAlice(in: app)
        let visibleRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "QA Person"))
            .allElementsBoundByIndex.first { $0.isHittable }
        guard let visibleRow else {
            XCTFail("Expected a visible fixture row after scrolling")
            return
        }
        let label = visibleRow.label
        let originalY = visibleRow.frame.minY

        app.buttons["Search"].tap()
        XCTAssertTrue(app.textFields["Name, place or note"].waitForExistence(timeout: 5))
        app.buttons["People"].tap()

        let returnedRow = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(waitUntil {
            returnedRow.exists && returnedRow.isHittable && abs(returnedRow.frame.minY - originalY) <= 12
        }, "Switching tabs should preserve People scroll position")
        XCTAssertFalse(alice(in: app).isHittable)
        XCTAssertFalse(app.staticTexts["person-name"].exists)
    }

    func testPeopleReselectFromDetailPopsToRoot() {
        let app = launch()
        let firstRow = alice(in: app)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        let originalY = firstRow.frame.minY
        firstRow.tap()
        XCTAssertTrue(app.staticTexts["person-name"].waitForExistence(timeout: 5))

        app.buttons["People"].tap()

        XCTAssertTrue(app.staticTexts["person-name"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Back"].exists)
        assertAtTop(app, originalY: originalY)
    }
}
