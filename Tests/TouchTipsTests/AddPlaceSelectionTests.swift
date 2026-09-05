@testable import TouchTips
import XCTest

final class AddPlaceSelectionTests: XCTestCase {
    private let nearby = PlaceChoice(key: "nearby", name: "Nearby", latitude: 38, longitude: -78)
    private let searched = PlaceChoice(key: "searched", name: "Searched", latitude: 39, longitude: -77)

    func testUntouchedSelectionUsesLocationSuggestion() {
        var selection = AddPlaceSelection()
        selection.suggest(nearby)
        XCTAssertEqual(selection.chosen, nearby)
    }

    func testSearchChoiceSurvivesLateLocationSuggestion() {
        var selection = AddPlaceSelection()
        // Search completes and the user picks a result before the location lookup returns.
        selection.choose(searched)
        selection.suggest(nearby)
        XCTAssertEqual(selection.chosen, searched)
    }

    func testExplicitNoPlaceSurvivesLateLocationSuggestion() {
        var selection = AddPlaceSelection()
        selection.choose(nil)
        selection.suggest(nearby)
        XCTAssertNil(selection.chosen)
    }

    func testUserCanReplaceAndClearAutomaticSuggestion() {
        var selection = AddPlaceSelection()
        selection.suggest(nearby)
        selection.choose(searched)
        XCTAssertEqual(selection.chosen, searched)
        selection.choose(nil)
        selection.suggest(nearby)
        XCTAssertNil(selection.chosen)
    }
}
