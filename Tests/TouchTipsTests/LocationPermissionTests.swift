import CoreLocation
@testable import TouchTips
import XCTest

final class LocationPermissionTests: XCTestCase {
    func testWhileUsingIsSufficientForOptionalForegroundLocation() {
        XCTAssertEqual(LocationPermissionAction(status: .notDetermined), .request)
        // No Always upgrade is needed for the shortcut or explicit foreground place capture.
        XCTAssertEqual(LocationPermissionAction(status: .authorizedWhenInUse), .allowed)
        XCTAssertEqual(LocationPermissionAction(status: .authorizedAlways), .allowed)
        XCTAssertEqual(LocationPermissionAction(status: .authorizedWhenInUse), .allowed)
    }

    func testExpiredAllowOnceCanRequestPermissionAgain() {
        XCTAssertEqual(LocationPermissionAction(status: .authorizedWhenInUse), .allowed)
        XCTAssertEqual(LocationPermissionAction(status: .notDetermined), .request)
    }

    func testDeniedOrRestrictedAccessDoesNotRetryTheSystemPrompt() {
        XCTAssertEqual(LocationPermissionAction(status: .denied), .openSettings)
        XCTAssertEqual(LocationPermissionAction(status: .restricted), .openSettings)
    }
}
