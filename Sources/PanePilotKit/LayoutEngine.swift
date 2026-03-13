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
    // MARK: - Edge-Based Frames

    func frame(for screen: CGRect, edge: SplitEdge, ratio: Double) -> CGRect {
        // Ratios come from UI and automation inputs, so clamp once here instead of
        // expecting each caller to sanitize the value the same way.
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

    // MARK: - Region-Based Frames

    func frame(for screen: CGRect, region: RegionLayout.Region) -> CGRect {
        // Region layouts store normalized coordinates in 0...1 space relative to the
        // visible display area, which keeps them portable across screen sizes.
        CGRect(
            x: screen.minX + (screen.width * region.normalizedFrame.minX),
            y: screen.minY + (screen.height * region.normalizedFrame.minY),
            width: screen.width * region.normalizedFrame.width,
            height: screen.height * region.normalizedFrame.height
        ).integral
    }
}
