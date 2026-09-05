@testable import TouchTips
import XCTest

@MainActor
final class ExplicitNavigationTests: XCTestCase {
    func testPlaceLinkOpensMapRootWithoutDiscardingSourceHistory() {
        let router = Router()
        router.paths[.people] = [.person("source")]
        router.paths[.map] = [.person("old")]
        router.showPlace(42)
        XCTAssertEqual(router.selectedTab, .map)
        XCTAssertTrue(router.isOnRoot)
        XCTAssertEqual(router.pendingPlace, 42)
        XCTAssertEqual(router.paths[.people], [.person("source")])
    }

    func testPlaceLinkFromMapPersonReturnsToMapRoot() {
        let router = Router()
        router.selectedTab = .map
        router.open(person: "a")
        router.showPlace(42)
        XCTAssertTrue(router.isOnRoot)
        XCTAssertEqual(router.pendingPlace, 42)
    }

    func testSearchReopensFieldFromRetainedPerson() {
        let router = Router()
        router.paths[.search] = [.person("old")]
        router.search()
        XCTAssertEqual(router.selectedTab, .search)
        XCTAssertTrue(router.isOnRoot)
        XCTAssertEqual(router.searchRequests, 1)
        router.open(person: "new")
        router.search()
        XCTAssertTrue(router.isOnRoot)
        XCTAssertEqual(router.searchRequests, 2)
    }
}
