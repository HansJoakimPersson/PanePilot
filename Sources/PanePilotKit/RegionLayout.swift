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

    static let column = makeColumns(
        id: "column",
        name: "3 Equal Columns",
        columnFractions: [1, 1, 1],
        regionNames: ["Left Column", "Center Column", "Right Column"]
    )

    static let threeColumnMiddle = makeColumns(
        id: "three-column-middle",
        name: "3 Column Main Center",
        columnFractions: [0.25, 0.5, 0.25],
        regionNames: ["Left Pane", "Main Pane", "Right Pane"]
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
        widescreenTall,
        widescreenTallMirror,
        column,
        threeColumnMiddle,
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
        case "three-column-left", "three-column-right":
            return threeColumnMiddle.id
        case "tall":
            return split60x40.id
        case "tall-right":
            return split40x60.id
        case "fullscreen":
            return split60x40.id
        case "wide":
            return split60x40.id
        case "wide-mirror":
            return split40x60.id
        case "row":
            return split40x60.id
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

}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
