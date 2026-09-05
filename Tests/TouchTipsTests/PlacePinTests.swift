import SwiftUI
@testable import TouchTips
import TouchTipsCore
import XCTest

@MainActor
final class PlacePinTests: XCTestCase {
    func testInitialsMarkerHasAnOpaqueInterior() throws {
        let rendered = try render(PlacePin(group: group(people: 1), tint: .blue))
        XCTAssertEqual(rendered.width, 40)
        XCTAssertEqual(rendered.height, 40)
        assertOpaqueInterior(rendered)
    }

    func testCountMarkerHasAnOpaqueInterior() throws {
        let rendered = try render(PlacePin(group: group(people: 12), tint: .blue))
        XCTAssertEqual(rendered.width, 44)
        XCTAssertEqual(rendered.height, 44)
        assertOpaqueInterior(rendered)
    }

    func testContactPhotoRemainsVisibleAndCircular() throws {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let rendered = try render(PlacePin(group: group(people: 1), image: photo, tint: .blue))
        XCTAssertEqual(rendered.width, 40)
        XCTAssertEqual(rendered.height, 40)
        let center = rendered.pixel(x: 20, y: 20)
        XCTAssertGreaterThan(center[0], 240)
        XCTAssertLessThan(center[1], 15)
        XCTAssertLessThan(center[2], 15)
        XCTAssertEqual(center[3], 255)
        // The corners may contain a faint shadow, but must not contain the square photo.
        XCTAssertLessThan(rendered.pixel(x: 0, y: 0)[3], 64)
    }

    private func group(people: Int) throws -> PlaceGroup {
        let sole = people == 1 ? #", "soleContactID": "alice", "soleName": "Alice Lee""# : ""
        let json = """
        {"id": 1, "key": "test", "latitude": 38, "longitude": -78,
         "people": \(people), "witnessed": true, "first": 0, "last": 0\(sole)}
        """
        return try PlaceGroup(places: [JSONDecoder().decode(PlaceSummary.self, from: Data(json.utf8))])
    }

    private func render(_ pin: PlacePin) throws -> RenderedPin {
        // Render onto transparency: every interior pixel must supply its own opaque backing.
        // This checks that contract, not the appearance of platform glass in ImageRenderer.
        let renderer = ImageRenderer(content: pin.environment(\.colorScheme, .dark))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress,
                width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return RenderedPin(width: image.width, height: image.height, pixels: pixels)
    }

    private func assertOpaqueInterior(
        _ rendered: RenderedPin, file: StaticString = #filePath, line: UInt = #line
    ) {
        let center = Double(rendered.width) / 2
        let radius = center - 4 // Exclude the border and antialiasing at the circle's edge.
        var minimumAlpha: UInt8 = 255
        for y in 0 ..< rendered.height {
            for x in 0 ..< rendered.width {
                let dx = Double(x) + 0.5 - center
                let dy = Double(y) + 0.5 - center
                if dx * dx + dy * dy < radius * radius {
                    minimumAlpha = min(minimumAlpha, rendered.pixel(x: x, y: y)[3])
                }
            }
        }
        XCTAssertEqual(minimumAlpha, 255, "Marker interior must hide the map beneath it", file: file, line: line)
    }
}

private struct RenderedPin {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    func pixel(x: Int, y: Int) -> [UInt8] {
        let offset = (y * width + x) * 4
        return Array(pixels[offset ..< offset + 4])
    }
}
