import XCTest

@MainActor
final class PersonSwipeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(layout: String = "default", search: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingDone", "YES", "-peopleLayout", layout]
        app.launchEnvironment["TOUCHTIPS_QA_SESSION"] = UUID().uuidString
        app.launchEnvironment["TOUCHTIPS_QA_DATA"] = "standard"
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15))
        if search {
            app.buttons["Search"].tap()
        }
        return app
    }

    private func alice(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "QA Alice")).firstMatch
    }

    private func openNote(_ app: XCUIApplication) {
        let row = alice(app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeRight()
        let note = app.buttons["person.swipe.note"]
        if note.waitForExistence(timeout: 1) {
            note.tap()
        }
        XCTAssertTrue(app.textFields["person.note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Focused note editor"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func notesRoundTrip(layout: String = "default", search: Bool = false) {
        let app = launch(layout: layout, search: search)
        openNote(app)
        let field = app.textFields["person.note"]
        field.typeText(" Swipe note")
        // Dismiss before the debounce; the final edit must still be persisted.
        app.navigationBars.buttons["Done"].tap()
        openNote(app)
        XCTAssertTrue((app.textFields["person.note"].value as? String)?.contains("Swipe note") == true)
        app.navigationBars.buttons["Done"].tap()
    }

    func testUndocumentedRowsAndListReuse() {
        let app = launch(search: true)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "QA Undocumented")).firstMatch
        for _ in 0 ..< 12 where !row.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(row.isHittable)
        XCTAssertTrue(row.label.contains("No meeting recorded"))
        XCTAssertFalse(row.label.contains("No meeting details"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Undocumented and reused list rows"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        row.swipeRight()
        let note = app.buttons["person.swipe.note"]
        if note.waitForExistence(timeout: 1) {
            note.tap()
        }
        XCTAssertTrue(app.textFields["person.note"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Done"].tap()
    }

    func testPeopleNotes() {
        notesRoundTrip()
    }

    func testTimelineNotes() {
        notesRoundTrip(layout: "timeline")
    }

    func testSearchNotes() {
        notesRoundTrip(search: true)
    }

    func testSwipeAppearanceAndTimelineScroll() {
        let app = launch(layout: "timeline")
        let row = alice(app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        let end = row.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.buttons["person.swipe.note"].waitForExistence(timeout: 5))
        let note = XCTAttachment(screenshot: app.screenshot())
        note.name = "Timeline note swipe"
        note.lifetime = .keepAlways
        add(note)
        // A vertical scroll should close the swipe and continue moving the native list.
        app.swipeUp()
        XCTAssertFalse(row.isHittable)
        app.buttons["People"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let left = row.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        end.press(forDuration: 0.05, thenDragTo: left)
        XCTAssertTrue(app.buttons["person.swipe.forget"].waitForExistence(timeout: 5))
        let forget = XCTAttachment(screenshot: app.screenshot())
        forget.name = "Timeline forget swipe"
        forget.lifetime = .keepAlways
        add(forget)
    }

    func testForgetCancelAndConfirm() {
        let app = launch()
        alice(app).swipeLeft()
        let action = app.buttons["person.swipe.forget"]
        if action.waitForExistence(timeout: 1) {
            action.tap()
        }
        let alert = app.alerts["Forget QA Alice?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(alice(app).exists)
        alice(app).swipeLeft()
        if action.waitForExistence(timeout: 1) {
            action.tap()
        }
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Forget"].tap()
        XCTAssertTrue(alice(app).waitForNonExistence(timeout: 5))
        app.buttons["Search"].tap()
        let row = alice(app)
        for _ in 0 ..< 12 where !row.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(row.isHittable, "The contact must remain in search after forgetting")
        row.tap()
        XCTAssertTrue(app.staticTexts["No meeting details"].waitForExistence(timeout: 5))
    }
}
