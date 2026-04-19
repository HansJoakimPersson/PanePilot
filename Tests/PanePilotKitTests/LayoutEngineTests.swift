import CoreGraphics
import XCTest
@testable import PanePilotKit

final class LayoutEngineTests: XCTestCase {
    // MARK: - Region Frames

    func testRegionFrameMapsNormalizedCoordinatesToDisplay() {
        let engine = LayoutEngine()
        let screen = CGRect(x: 50, y: 20, width: 1000, height: 600)
        let region = RegionLayout.Region(
            id: 2,
            name: "Right Half",
            normalizedFrame: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        )

        let frame = engine.frame(for: screen, region: region)

        XCTAssertEqual(frame, CGRect(x: 550, y: 20, width: 500, height: 600))
    }

    func testFullScreenRegionCoversEntireScreen() {
        let engine = LayoutEngine()
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let region = RegionLayout.Region(
            id: 1,
            name: "Full",
            normalizedFrame: CGRect(x: 0, y: 0, width: 1, height: 1)
        )

        let frame = engine.frame(for: screen, region: region)

        XCTAssertEqual(frame, screen)
    }

    func testRegionFrameRespectsScreenOffset() {
        let engine = LayoutEngine()
        // Simulate a secondary display positioned to the right of the primary.
        let screen = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let region = RegionLayout.Region(
            id: 1,
            name: "Left Third",
            normalizedFrame: CGRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1)
        )

        let frame = engine.frame(for: screen, region: region)

        XCTAssertEqual(frame.minX, 1440)
        XCTAssertEqual(frame.width, (1920.0 / 3.0).rounded())
        XCTAssertEqual(frame.height, 1080)
    }

    func testRegionFrameIsIntegral() {
        let engine = LayoutEngine()
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)
        // 1/3 of 1000 = 333.333… — should be rounded to a whole-pixel value.
        let region = RegionLayout.Region(
            id: 1,
            name: "Third",
            normalizedFrame: CGRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1)
        )

        let frame = engine.frame(for: screen, region: region)

        XCTAssertEqual(frame.origin.x, frame.origin.x.rounded())
        XCTAssertEqual(frame.origin.y, frame.origin.y.rounded())
        XCTAssertEqual(frame.width, frame.width.rounded())
        XCTAssertEqual(frame.height, frame.height.rounded())
    }
}
