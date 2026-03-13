import CoreGraphics
import Foundation

struct RegionLayout: Codable {
    struct Region: Codable {
        let id: Int
        let name: String
        // Stored in normalized 0...1 display coordinates so layouts scale to any screen.
        let normalizedFrame: CGRect
    }

    let id: String
    let name: String
    let regions: [Region]
}

enum RegionLayouts {
    private enum ThreeColumnMainPosition {
        case left
        case center
        case right
    }

    // MARK: - Built-In Layouts

    static let split40x60 = makeColumns(
        id: "split-40-60",
        name: "40 / 60",
        columnFractions: [0.4, 0.6],
        regionNames: ["Left Pane", "Right Pane"]
    )

    static let split60x40 = makeColumns(
        id: "split-60-40",
        name: "60 / 40",
        columnFractions: [0.6, 0.4],
        regionNames: ["Left Pane", "Right Pane"]
    )

    static let wide = makeWide(
        id: "wide",
        name: "Wide",
        mainOnTop: true,
        mainFraction: 0.5
    )

    static let wideMirror = makeWide(
        id: "wide-mirror",
        name: "Wide Mirror",
        mainOnTop: false,
        mainFraction: 0.5
    )

    static let column = makeColumns(
        id: "column",
        name: "3 Equal Columns",
        columnFractions: [1, 1, 1],
        regionNames: ["Left Column", "Center Column", "Right Column"]
    )

    static let threeColumnLeft = makeThreeColumn(
        id: "three-column-left",
        name: "3 Column Main Left",
        mainPosition: .left
    )

    static let threeColumnMiddle = makeThreeColumn(
        id: "three-column-middle",
        name: "3 Column Main Center",
        mainPosition: .center
    )

    static let threeColumnRight = makeThreeColumn(
        id: "three-column-right",
        name: "3 Column Main Right",
        mainPosition: .right
    )

    static let widescreenTall = RegionLayout(
        id: "widescreen-tall",
        name: "Widescreen Left",
        regions: [
            .init(id: 1, name: "Main Pane", normalizedFrame: CGRect(x: 0, y: 0, width: 2.0 / 3.0, height: 1)),
            .init(id: 2, name: "Upper Stack", normalizedFrame: CGRect(x: 2.0 / 3.0, y: 0.5, width: 1.0 / 3.0, height: 0.5)),
            .init(id: 3, name: "Lower Stack", normalizedFrame: CGRect(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 0.5)),
        ]
    )

    static let widescreenTallMirror = RegionLayout(
        id: "widescreen-tall-mirror",
        name: "Widescreen Right",
        regions: [
            .init(id: 1, name: "Lower Stack", normalizedFrame: CGRect(x: 0, y: 0, width: 1.0 / 3.0, height: 0.5)),
            .init(id: 2, name: "Upper Stack", normalizedFrame: CGRect(x: 0, y: 0.5, width: 1.0 / 3.0, height: 0.5)),
            .init(id: 3, name: "Main Pane", normalizedFrame: CGRect(x: 1.0 / 3.0, y: 0, width: 2.0 / 3.0, height: 1)),
        ]
    )

    static let all: [RegionLayout] = [
        split40x60,
        split60x40,
        wide,
        wideMirror,
        column,
        widescreenTall,
        widescreenTallMirror,
        threeColumnLeft,
        threeColumnMiddle,
        threeColumnRight,
    ]

    // MARK: - Lookup

    static func find(by id: String) -> RegionLayout? {
        let normalizedID = canonicalLayoutID(for: id)
        return all.first { $0.id == normalizedID }
    }

    // MARK: - Factories

    static func canonicalLayoutID(for id: String) -> String {
        switch id.lowercased() {
        case "split-20-80":
            return split40x60.id
        case "split-80-20":
            return split60x40.id
        case "three-column":
            return column.id
        case "tall":
            return split60x40.id
        case "tall-right":
            return split40x60.id
        case "fullscreen":
            return split60x40.id
        case "row":
            return wideMirror.id
        default:
            return id.lowercased()
        }
    }

    static func makeColumns(id: String, name: String, columnFractions: [CGFloat], regionNames: [String]? = nil) -> RegionLayout {
        let total = columnFractions.reduce(0, +)
        let normalized = total > 0 ? columnFractions.map { $0 / total } : [1.0]

        var x: CGFloat = 0
        var regions: [RegionLayout.Region] = []
        for (index, width) in normalized.enumerated() {
            let region = RegionLayout.Region(
                id: index + 1,
                name: regionNames?[safe: index] ?? "Column \(index + 1)",
                normalizedFrame: CGRect(x: x, y: 0, width: width, height: 1)
            )
            regions.append(region)
            x += width
        }

        return RegionLayout(id: id, name: name, regions: regions)
    }

    static func makeRows(id: String, name: String, rowFractions: [CGFloat], regionNames: [String]? = nil) -> RegionLayout {
        let total = rowFractions.reduce(0, +)
        let normalized = total > 0 ? rowFractions.map { $0 / total } : [1.0]

        var y: CGFloat = 0
        var regions: [RegionLayout.Region] = []
        for (index, height) in normalized.enumerated() {
            let region = RegionLayout.Region(
                id: index + 1,
                name: regionNames?[safe: index] ?? "Row \(index + 1)",
                normalizedFrame: CGRect(x: 0, y: y, width: 1, height: height)
            )
            regions.append(region)
            y += height
        }

        return RegionLayout(id: id, name: name, regions: regions)
    }

    private static func makeWide(id: String, name: String, mainOnTop: Bool, mainFraction: CGFloat) -> RegionLayout {
        let fractions = mainOnTop ? [1 - mainFraction, mainFraction] : [mainFraction, 1 - mainFraction]
        let names = mainOnTop ? ["Stack Pane", "Main Pane"] : ["Main Pane", "Stack Pane"]
        return makeRows(id: id, name: name, rowFractions: fractions, regionNames: names)
    }

    private static func makeThreeColumn(id: String, name: String, mainPosition: ThreeColumnMainPosition) -> RegionLayout {
        switch mainPosition {
        case .left:
            return makeColumns(
                id: id,
                name: name,
                columnFractions: [0.5, 0.25, 0.25],
                regionNames: ["Main Pane", "Secondary Pane", "Tertiary Pane"]
            )
        case .center:
            return makeColumns(
                id: id,
                name: name,
                columnFractions: [0.25, 0.5, 0.25],
                regionNames: ["Left Pane", "Main Pane", "Right Pane"]
            )
        case .right:
            return makeColumns(
                id: id,
                name: name,
                columnFractions: [0.25, 0.25, 0.5],
                regionNames: ["Tertiary Pane", "Secondary Pane", "Main Pane"]
            )
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
