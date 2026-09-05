import XCTest

@MainActor
final class NotificationUITests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(person: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingDone", "YES"]
        app.launchEnvironment["TOUCHTIPS_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["TOUCHTIPS_TEST_PERSON"] = person
        app.launch()
        if springboard.alerts.buttons["Allow"].waitForExistence(timeout: 3) {
            springboard.alerts.buttons["Allow"].tap()
        }
        return app
    }

    private func notification(name: String = "Notification Test Person") -> XCUIElement {
        springboard.buttons.matching(NSPredicate(
            format: "identifier == 'ListCell' AND label CONTAINS %@",
            name
        )).firstMatch
    }

    private func openNotificationCenter(_ app: XCUIApplication) {
        // Start away from the Dynamic Island so this is a Notification Center edge gesture.
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.01))
        top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
    }

    private func tapNotification(_ notice: XCUIElement, in app: XCUIApplication) {
        notice.swipeRight()
        let open = springboard.buttons["Open"]
        if open.waitForExistence(timeout: 2) {
            open.tap()
        }
    }

    func testWarmNotificationTapAndBack() {
        let app = launch(person: "warm-person")
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.buttons["Map"].tap()
        openNotificationCenter(app)
        let notice = notification()
        XCTAssertTrue(notice.waitForExistence(timeout: 8), springboard.debugDescription)
        tapNotification(notice, in: app)
        XCTAssertTrue(app.staticTexts["person-name"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["person-name"].label, "Notification Test Person")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
    }

    func testColdNotificationTap() {
        let app = launch(person: "cold-person")
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        openNotificationCenter(app)
        XCTAssertTrue(notification().waitForExistence(timeout: 8))
        app.terminate()
        tapNotification(notification(), in: app)
        XCTAssertTrue(app.staticTexts["person-name"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["person-name"].label, "Notification Test Person")
    }

    func testRemovedContactNotificationShowsFallback() {
        let app = launch(person: "removed-person")
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchEnvironment["TOUCHTIPS_TEST_PERSON"] = nil
        app.launchEnvironment["TOUCHTIPS_DELETE_PERSON"] = "removed-person"
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        openNotificationCenter(app)
        XCTAssertTrue(notification().waitForExistence(timeout: 8))
        tapNotification(notification(), in: app)
        XCTAssertTrue(app.staticTexts["Contact unavailable"].waitForExistence(timeout: 10))
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
    }

    func testExternalContactsAppSaveAndNotificationTap() {
        let app = launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Reading your contacts"].waitForNonExistence(timeout: 10))
        let contacts = XCUIApplication(bundleIdentifier: "com.apple.MobileAddressBook")
        contacts.launch()
        if contacts.buttons["Continue"].waitForExistence(timeout: 2) {
            contacts.buttons["Continue"].tap()
        }
        let add = contacts.buttons["Add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), contacts.debugDescription)
        add.tap()
        let name = "ContactUITest \(UUID().uuidString.prefix(8))"
        let firstName = contacts.textFields["First name"]
        XCTAssertTrue(firstName.waitForExistence(timeout: 5))
        firstName.tap()
        firstName.typeText(name)
        contacts.buttons["Done"].tap()
        app.activate()
        openNotificationCenter(app)
        let notice = notification(name: name)
        XCTAssertTrue(notice.waitForExistence(timeout: 10), springboard.debugDescription)
        tapNotification(notice, in: app)
        XCTAssertTrue(app.staticTexts["person-name"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["person-name"].label, name)
    }

    func testInAppContactSaveAndNotificationTap() {
        let app = launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Reading your contacts"].waitForNonExistence(timeout: 10))
        app.buttons["Add"].tap()
        let field = app.textFields["Name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let name = "InAppUITest \(UUID().uuidString.prefix(8))"
        field.tap()
        field.typeText(name)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        openNotificationCenter(app)
        let notice = notification(name: name)
        XCTAssertTrue(notice.waitForExistence(timeout: 15), springboard.debugDescription)
        tapNotification(notice, in: app)
        XCTAssertTrue(app.staticTexts["person-name"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["person-name"].label, name)
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
    }
}
