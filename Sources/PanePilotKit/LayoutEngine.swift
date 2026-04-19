import CoreGraphics
import Foundation

/// Pure geometry calculations for window placement.
///
/// `LayoutEngine` is a stateless struct that converts normalised region frames into
/// pixel-aligned `CGRect` values suitable for passing to the Accessibility API. All methods
/// are deterministic given the same inputs and carry no side-effects.
struct LayoutEngine {
    // MARK: - Region-Based Frames

    /// Returns the pixel-aligned frame for the given normalised region within `screen`.
    ///
    /// `region.normalizedFrame` is in 0…1 space relative to the screen's visible area.
    /// Multiplying by the screen's width and height converts it to absolute coordinates, and
    /// `.integral` snaps sub-pixel values to whole-pixel boundaries.
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
