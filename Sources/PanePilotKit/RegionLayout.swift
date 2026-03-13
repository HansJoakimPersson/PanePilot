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

    static let split20x80 = makeColumns(
        id: "split-20-80",
        name: "20 / 80",
        columnFractions: [0.2, 0.8]
    )

    static let split80x20 = makeColumns(
        id: "split-80-20",
        name: "80 / 20",
        columnFractions: [0.8, 0.2]
    )

    static let threeColumn = RegionLayout(
        id: "three-column",
        name: "Three Column",
        regions: [
            .init(id: 1, name: "Left Third", normalizedFrame: CGRect(x: 0.0, y: 0.0, width: 1.0 / 3.0, height: 1.0)),
            .init(id: 2, name: "Center Third", normalizedFrame: CGRect(x: 1.0 / 3.0, y: 0.0, width: 1.0 / 3.0, height: 1.0)),
            .init(id: 3, name: "Right Third", normalizedFrame: CGRect(x: 2.0 / 3.0, y: 0.0, width: 1.0 / 3.0, height: 1.0)),
        ]
    )

    static let all: [RegionLayout] = [
        split20x80,
        split80x20,
        threeColumn,
    ]

    // MARK: - Lookup

    static func find(by id: String) -> RegionLayout? {
        all.first { $0.id == id.lowercased() }
    }

    // MARK: - Factories

    static func makeColumns(id: String, name: String, columnFractions: [CGFloat]) -> RegionLayout {
        let total = columnFractions.reduce(0, +)
        let normalized = total > 0 ? columnFractions.map { $0 / total } : [1.0]

        var x: CGFloat = 0
        var regions: [RegionLayout.Region] = []
        for (index, width) in normalized.enumerated() {
            let region = RegionLayout.Region(
                id: index + 1,
                name: "Column \(index + 1)",
                normalizedFrame: CGRect(x: x, y: 0, width: width, height: 1)
            )
            regions.append(region)
            x += width
        }

        return RegionLayout(id: id, name: name, regions: regions)
    }
}
