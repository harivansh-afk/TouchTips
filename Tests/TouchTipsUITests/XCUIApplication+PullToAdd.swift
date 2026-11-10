import XCTest

extension XCUIApplication {
    /// Pulls the People list down past the ring's threshold and lets go, which opens the Add sheet.
    /// The list rubber-bands, so the drag is longer than the threshold itself.
    func pullToAdd() {
        let list = collectionViews.firstMatch.exists ? collectionViews.firstMatch : self
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = start.withOffset(CGVector(dx: 0, dy: 320))
        start.press(
            forDuration: 0.05, thenDragTo: end, withVelocity: XCUIGestureVelocity.slow, thenHoldForDuration: 0.2
        )
    }
}
