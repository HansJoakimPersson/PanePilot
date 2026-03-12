import XCTest
@testable import PanePilotKit

final class RegionLayoutsTests: XCTestCase {
    func testBuiltInLayoutsStayAvailable() {
        XCTAssertEqual(RegionLayouts.all.map(\.id), [
            "split-20-80",
            "split-80-20",
            "three-column",
        ])
    }

    func testThreeColumnLayoutCoversEntireWidth() throws {
        let layout = try XCTUnwrap(RegionLayouts.find(by: "three-column"))
        let totalWidth = layout.regions.reduce(0) { $0 + $1.normalizedFrame.width }

        XCTAssertEqual(layout.regions.count, 3)
        XCTAssertEqual(totalWidth, 1.0, accuracy: 0.0001)
    }
}
