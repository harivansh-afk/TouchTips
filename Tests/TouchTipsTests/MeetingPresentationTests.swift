import Foundation
@testable import TouchTips
import TouchTipsCore
import XCTest

final class MeetingPresentationTests: XCTestCase {
    func testSuggestedRangeIsNotPresentedAsItsFirstDay() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(7 * 86400)
        var meet = Meet(
            contactID: "a", start: start, end: end, precision: .month, placeID: nil,
            tier: .dateOnly, userSet: false, addSeenStart: start, addSeenEnd: end, computedAt: end
        )
        XCTAssertEqual(Format.headline(for: meet).lead, "Sometime between")
        XCTAssertTrue(Format.headline(for: meet).body.contains(Format.longDate(end)))
        XCTAssertTrue(Format.dateLine(meet).contains(Format.longDate(end)))
        XCTAssertTrue(Format.rowDate(meet).contains("–"))
        meet.dateConfirmed = true
        meet.placeConfirmed = true
        XCTAssertEqual(Format.headline(for: meet).lead, "Sometime between")
        XCTAssertTrue(Format.dateLine(meet).contains(Format.longDate(end)))
    }

    func testUnnamedAndCoordinatePlaceLabelsStayReadable() {
        for name in [nil, "", "  \n", "38.029300, -78.476700", " 38.029, -78.477 "] as [String?] {
            XCTAssertEqual(Format.placeLabel(name, latitude: 38.0293, longitude: -78.4767), "Meeting location")
        }
        XCTAssertEqual(Format.placeLabel("  123 Main Street  ", latitude: 0, longitude: 0), "123 Main Street")
    }

    func testSuggestionsHideUnnamedEntriesAndDeduplicateByPlace() {
        let unnamed = PlaceChoice(key: "a", name: "Meeting location", latitude: 0, longitude: 0)
        let named = PlaceChoice(key: "a", name: "Coffee", latitude: 0, longitude: 0)
        let otherPlace = PlaceChoice(key: "b", name: "Park", latitude: 1, longitude: 1)
        let choices = PlaceChoice.suggestions(picked: [unnamed, unnamed], candidates: [named, named, otherPlace])
        XCTAssertEqual(choices.map(\.key), ["a", "b"])
        XCTAssertEqual(choices.map(\.name), ["Coffee", "Park"])
        XCTAssertTrue(PlaceChoice.suggestions(picked: [unnamed], candidates: [unnamed]).isEmpty)
    }
    func testRepeatedPlaceNamesUseTheSelectedRecordAcrossDifferentKeys() {
        let visit = PlaceChoice(key: "visit", name: "Café  Central", latitude: 38, longitude: -78)
        let search = PlaceChoice(key: "search", name: " cafe central ", latitude: 38.0001, longitude: -78)
        let selected = PlaceChoice(key: "saved", name: "Café Central", latitude: 38, longitude: -78)
        let choices = PlaceChoice.suggestions(picked: [search], candidates: [visit], selection: selected)
        XCTAssertEqual(choices.map(\.key), ["saved"])
        XCTAssertEqual(choices.map(\.name), ["Café Central"])
        XCTAssertEqual(PlaceChoice.suggestions(picked: [search], candidates: [visit]).count, 1)
    }

}
