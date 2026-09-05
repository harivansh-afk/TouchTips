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
}
