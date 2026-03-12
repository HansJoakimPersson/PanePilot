import CoreGraphics
import Foundation

enum SplitEdge: String {
    case left
    case right
    case top
    case bottom

    init(from raw: String) throws {
        guard let edge = SplitEdge(rawValue: raw.lowercased()) else {
            throw AppError.invalidArguments("Invalid edge '\(raw)'. Use: left|right|top|bottom")
        }
        self = edge
    }
}

struct LayoutEngine {
    func frame(for screen: CGRect, edge: SplitEdge, ratio: Double) -> CGRect {
        let clamped = min(max(ratio, 0.0), 1.0)
        let width = screen.width
        let height = screen.height

        switch edge {
        case .left:
            return CGRect(
                x: screen.minX,
                y: screen.minY,
                width: width * clamped,
                height: height
            ).integral
        case .right:
            let targetWidth = width * clamped
            return CGRect(
                x: screen.maxX - targetWidth,
                y: screen.minY,
                width: targetWidth,
                height: height
            ).integral
        case .top:
            let targetHeight = height * clamped
            return CGRect(
                x: screen.minX,
                y: screen.maxY - targetHeight,
                width: width,
                height: targetHeight
            ).integral
        case .bottom:
            return CGRect(
                x: screen.minX,
                y: screen.minY,
                width: width,
                height: height * clamped
            ).integral
        }
    }

    func frame(for screen: CGRect, region: RegionLayout.Region) -> CGRect {
        CGRect(
            x: screen.minX + (screen.width * region.normalizedFrame.minX),
            y: screen.minY + (screen.height * region.normalizedFrame.minY),
            width: screen.width * region.normalizedFrame.width,
            height: screen.height * region.normalizedFrame.height
        ).integral
    }
}
