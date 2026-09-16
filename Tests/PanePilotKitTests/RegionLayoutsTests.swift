import XCTest
@testable import PanePilotKit

final class RegionLayoutsTests: XCTestCase {
    // MARK: - Built-In Layouts

    func testBuiltInLayoutsStayAvailable() {
        XCTAssertEqual(RegionLayouts.all.map(\.id), [
            "split-40-60",
            "split-60-40",
            "widescreen-tall",
            "widescreen-tall-mirror",
            "column",
            "three-column-middle",
        ])
    }

    func testLegacyBuiltInIDsResolveToCurrentLayouts() {
        XCTAssertEqual(RegionLayouts.find(by: "split-20-80")?.id, "split-40-60")
        XCTAssertEqual(RegionLayouts.find(by: "split-80-20")?.id, "split-60-40")
        XCTAssertEqual(RegionLayouts.find(by: "three-column")?.id, "column")
        XCTAssertEqual(RegionLayouts.find(by: "three-column-left")?.id, "three-column-middle")
        XCTAssertEqual(RegionLayouts.find(by: "three-column-right")?.id, "three-column-middle")
        XCTAssertEqual(RegionLayouts.find(by: "tall")?.id, "split-60-40")
        XCTAssertEqual(RegionLayouts.find(by: "tall-right")?.id, "split-40-60")
        XCTAssertEqual(RegionLayouts.find(by: "wide")?.id, "split-60-40")
        XCTAssertEqual(RegionLayouts.find(by: "wide-mirror")?.id, "split-40-60")
    }

    func testThreeEqualColumnsCoverEntireWidth() throws {
        let layout = try XCTUnwrap(RegionLayouts.find(by: "column"))
        let totalWidth = layout.regions.reduce(0) { $0 + $1.normalizedFrame.width }

        XCTAssertEqual(layout.regions.count, 3)
        XCTAssertEqual(totalWidth, 1.0, accuracy: 0.0001)
        XCTAssertEqual(layout.regions.map(\.name), ["Left Column", "Center Column", "Right Column"])
        XCTAssertEqual(layout.regions.map(\.id), [1, 2, 3])
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

    func testWidescreenLeftNumbersMainPaneBeforeRightStackTopToBottom() throws {
        let layout = try XCTUnwrap(RegionLayouts.find(by: "widescreen-tall"))
        let mainPane = try XCTUnwrap(layout.regions.first(where: { $0.name == "Main Pane" }))
        let upperPane = try XCTUnwrap(layout.regions.first(where: { $0.name == "Upper Stack" }))
        let lowerPane = try XCTUnwrap(layout.regions.first(where: { $0.name == "Lower Stack" }))

        XCTAssertEqual(mainPane.id, 1)
        XCTAssertEqual(upperPane.id, 2)
        XCTAssertEqual(lowerPane.id, 3)
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

    func testWidescreenMirrorNumbersLeftStackTopToBottomBeforeMainPane() throws {
        let layout = try XCTUnwrap(RegionLayouts.find(by: "widescreen-tall-mirror"))
        let upperPane = try XCTUnwrap(layout.regions.first(where: { $0.name == "Upper Stack" }))
        let lowerPane = try XCTUnwrap(layout.regions.first(where: { $0.name == "Lower Stack" }))

        let mainPane = try XCTUnwrap(layout.regions.first(where: { $0.name == "Main Pane" }))

        XCTAssertEqual(upperPane.id, 1)
        XCTAssertEqual(lowerPane.id, 2)
        XCTAssertEqual(mainPane.id, 3)
    }
}
