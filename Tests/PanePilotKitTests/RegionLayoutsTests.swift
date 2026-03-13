import XCTest
@testable import PanePilotKit

final class RegionLayoutsTests: XCTestCase {
    // MARK: - Built-In Layouts

    func testBuiltInLayoutsStayAvailable() {
        XCTAssertEqual(RegionLayouts.all.map(\.id), [
            "split-40-60",
            "split-60-40",
            "wide",
            "wide-mirror",
            "column",
            "widescreen-tall",
            "widescreen-tall-mirror",
            "three-column-left",
            "three-column-middle",
            "three-column-right",
        ])
    }

    func testLegacyBuiltInIDsResolveToCurrentLayouts() {
        XCTAssertEqual(RegionLayouts.find(by: "split-20-80")?.id, "split-40-60")
        XCTAssertEqual(RegionLayouts.find(by: "split-80-20")?.id, "split-60-40")
        XCTAssertEqual(RegionLayouts.find(by: "three-column")?.id, "column")
        XCTAssertEqual(RegionLayouts.find(by: "tall")?.id, "split-60-40")
        XCTAssertEqual(RegionLayouts.find(by: "tall-right")?.id, "split-40-60")
    }

    func testThreeEqualColumnsCoverEntireWidth() throws {
        let layout = try XCTUnwrap(RegionLayouts.find(by: "column"))
        let totalWidth = layout.regions.reduce(0) { $0 + $1.normalizedFrame.width }

        XCTAssertEqual(layout.regions.count, 3)
        XCTAssertEqual(totalWidth, 1.0, accuracy: 0.0001)
    }

    func testWidescreenLeftKeepsMainPaneDominant() throws {
        let layout = try XCTUnwrap(RegionLayouts.find(by: "widescreen-tall"))
        let mainPane = try XCTUnwrap(layout.regions.first(where: { $0.name == "Main Pane" }))
        let stackedHeight = layout.regions
            .filter { $0.name != "Main Pane" }
            .reduce(0) { $0 + $1.normalizedFrame.height }

        XCTAssertEqual(layout.regions.count, 3)
        XCTAssertGreaterThan(mainPane.normalizedFrame.width, 0.5)
        XCTAssertEqual(stackedHeight, 1.0, accuracy: 0.0001)
    }

    func testWidescreenMirrorKeepsMainPaneDominant() throws {
        let layout = try XCTUnwrap(RegionLayouts.find(by: "widescreen-tall-mirror"))
        let mainPane = try XCTUnwrap(layout.regions.first(where: { $0.name == "Main Pane" }))
        let stackedHeight = layout.regions
            .filter { $0.name != "Main Pane" }
            .reduce(0) { $0 + $1.normalizedFrame.height }

        XCTAssertEqual(layout.regions.count, 3)
        XCTAssertGreaterThan(mainPane.normalizedFrame.width, 0.5)
        XCTAssertEqual(mainPane.normalizedFrame.maxX, 1.0, accuracy: 0.0001)
        XCTAssertEqual(stackedHeight, 1.0, accuracy: 0.0001)
    }
}
