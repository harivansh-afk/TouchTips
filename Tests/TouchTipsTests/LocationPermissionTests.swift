import CoreLocation
@testable import TouchTips
import XCTest

final class LocationPermissionTests: XCTestCase {
    func testWhileUsingCanRecoverWithoutRepeatingAnIgnoredPrompt() {
        XCTAssertEqual(LocationPermissionAction(status: .notDetermined), .request)
        // Core Location reports the same status after While Using, Allow Once, and declining
        // the Always upgrade. Every case must provide a working route to enable background capture.
        XCTAssertEqual(LocationPermissionAction(status: .authorizedWhenInUse), .openSettings)
        XCTAssertEqual(LocationPermissionAction(status: .authorizedAlways), .allowed)
        // A later downgrade in Settings must restore that recovery route.
        XCTAssertEqual(LocationPermissionAction(status: .authorizedWhenInUse), .openSettings)
    }

    func testExpiredAllowOnceCanRequestPermissionAgain() {
        XCTAssertEqual(LocationPermissionAction(status: .authorizedWhenInUse), .openSettings)
        XCTAssertEqual(LocationPermissionAction(status: .notDetermined), .request)
    }

    func testDeniedOrRestrictedAccessDoesNotRetryTheSystemPrompt() {
        XCTAssertEqual(LocationPermissionAction(status: .denied), .openSettings)
        XCTAssertEqual(LocationPermissionAction(status: .restricted), .openSettings)
    }
}
