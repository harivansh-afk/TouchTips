import MapKit
@testable import TouchTips
import XCTest

final class InitialMapFramingTests: XCTestCase {
    func testOnePlaceGetsStreetContext() throws {
        let coordinate = CLLocationCoordinate2D(latitude: 38.03, longitude: -78.48)
        let region = try XCTUnwrap(InitialMapFraming.region(containing: [coordinate]))
        XCTAssertEqual(region.center.latitude, coordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(region.center.longitude, coordinate.longitude, accuracy: 0.000001)
        XCTAssertGreaterThan(region.span.latitudeDelta, 0)
        XCTAssertLessThan(region.span.latitudeDelta, 0.02)
        XCTAssertGreaterThan(region.span.longitudeDelta, 0)
        XCTAssertLessThan(region.span.longitudeDelta, 0.02)
    }

    func testFitIncludesSeparatedPlacesWithPadding() throws {
        let places = [
            CLLocationCoordinate2D(latitude: 38, longitude: -79),
            CLLocationCoordinate2D(latitude: 40, longitude: -74),
        ]
        let region = try XCTUnwrap(InitialMapFraming.region(containing: places))
        for place in places {
            XCTAssertLessThan(abs(place.latitude - region.center.latitude), region.span.latitudeDelta / 2)
            XCTAssertLessThan(
                longitudeDistance(place.longitude, region.center.longitude),
                region.span.longitudeDelta / 2
            )
        }
    }

    func testDatelinePlacesUseTheShortLongitudeSpan() throws {
        let places = [
            CLLocationCoordinate2D(latitude: 10, longitude: 179),
            CLLocationCoordinate2D(latitude: 10, longitude: -179),
        ]
        let region = try XCTUnwrap(InitialMapFraming.region(containing: places))
        XCTAssertEqual(abs(region.center.longitude), 180, accuracy: 0.000001)
        XCTAssertLessThan(region.span.longitudeDelta, 3)
        for place in places {
            XCTAssertLessThan(
                longitudeDistance(place.longitude, region.center.longitude),
                region.span.longitudeDelta / 2
            )
        }
    }

    func testCoordinateExtremesKeepRegionWithinValidBounds() throws {
        for coordinates in [
            [CLLocationCoordinate2D(latitude: 90, longitude: 180)],
            [CLLocationCoordinate2D(latitude: -90, longitude: -180)],
            [
                CLLocationCoordinate2D(latitude: -90, longitude: -180),
                CLLocationCoordinate2D(latitude: 90, longitude: 180),
            ],
        ] {
            let region = try XCTUnwrap(InitialMapFraming.region(containing: coordinates))
            XCTAssertTrue(CLLocationCoordinate2DIsValid(region.center))
            XCTAssertTrue(region.span.latitudeDelta.isFinite)
            XCTAssertTrue(region.span.longitudeDelta.isFinite)
            XCTAssertGreaterThan(region.span.latitudeDelta, 0)
            XCTAssertGreaterThan(region.span.longitudeDelta, 0)
            XCTAssertLessThanOrEqual(region.span.latitudeDelta, 180)
            XCTAssertLessThanOrEqual(region.span.longitudeDelta, 360)
            XCTAssertLessThanOrEqual(abs(region.center.latitude) + region.span.latitudeDelta / 2, 90)
        }
    }

    func testEmptyAndInvalidCoordinatesDoNotProduceACamera() throws {
        let invalid = [
            CLLocationCoordinate2D(latitude: .nan, longitude: 0),
            CLLocationCoordinate2D(latitude: 91, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 181),
            CLLocationCoordinate2D(latitude: 0, longitude: .infinity),
        ]
        XCTAssertNil(InitialMapFraming.region(containing: []))
        XCTAssertNil(InitialMapFraming.region(containing: invalid))
        let valid = CLLocationCoordinate2D(latitude: 38, longitude: -78)
        let region = try XCTUnwrap(InitialMapFraming.region(containing: invalid + [valid]))
        XCTAssertEqual(region.center.latitude, valid.latitude, accuracy: 0.000001)
    }

    func testFirstSnapshotIsTheOnlyAutomaticFit() {
        let coordinate = CLLocationCoordinate2D(latitude: 38, longitude: -78)
        var framing = InitialMapFraming()
        XCTAssertNotNil(framing.region(afterLoading: [coordinate], hasPendingPlace: false, positionedByUser: false))
        XCTAssertNil(framing.region(afterLoading: [coordinate], hasPendingPlace: false, positionedByUser: false))

        var empty = InitialMapFraming()
        XCTAssertNil(empty.region(afterLoading: [], hasPendingPlace: false, positionedByUser: false))
        XCTAssertNil(empty.region(afterLoading: [coordinate], hasPendingPlace: false, positionedByUser: false))
    }

    func testPendingPlaceAndUserChoicesPreventInitialFit() {
        let coordinate = CLLocationCoordinate2D(latitude: 38, longitude: -78)
        for (pending, user) in [(true, false), (false, true)] {
            var framing = InitialMapFraming()
            XCTAssertNil(framing.region(afterLoading: [coordinate], hasPendingPlace: pending, positionedByUser: user))
            XCTAssertNil(framing.region(afterLoading: [coordinate], hasPendingPlace: false, positionedByUser: false))
        }
        var recentered = InitialMapFraming()
        recentered.cancel()
        XCTAssertNil(recentered.region(afterLoading: [coordinate], hasPendingPlace: false, positionedByUser: false))
    }

    private func longitudeDistance(_ first: Double, _ second: Double) -> Double {
        let distance = abs(first - second)
        return min(distance, 360 - distance)
    }
}
