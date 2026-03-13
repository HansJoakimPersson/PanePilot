import CoreGraphics
import XCTest
@testable import PanePilotKit

final class LayoutEngineTests: XCTestCase {
    // MARK: - Edge Frames

    func testLeftEdgeFrameClampsRatioAboveOne() {
        let engine = LayoutEngine()
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

        let frame = engine.frame(for: screen, edge: .left, ratio: 1.5)

        XCTAssertEqual(frame, screen)
    }

    func testTopEdgeFrameUsesUpperPortionOfScreen() {
        let engine = LayoutEngine()
        let screen = CGRect(x: 100, y: 50, width: 1200, height: 800)

        let frame = engine.frame(for: screen, edge: .top, ratio: 0.25)

        XCTAssertEqual(frame, CGRect(x: 100, y: 650, width: 1200, height: 200))
    }

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
}
