import AppKit
import Foundation

/// Programmatic image factory for all app icon surfaces.
///
/// PanePilot ships no `.xcassets` asset catalog — icons are generated at runtime using Core
/// Graphics primitives. This avoids asset-catalog tooling requirements during SwiftPM and
/// `make run` builds and ensures the icon is always available regardless of bundle structure.
///
/// All three entry points return `NSImage` instances ready to hand to AppKit or SwiftUI.
public enum AppIconProvider {
    // MARK: - Public Images

    /// Returns the best available full-size application icon.
    ///
    /// Resolution order:
    /// 1. `NSImage(named: "AppIcon")` — picks up the asset if the bundle was built by Xcode.
    /// 2. `AppIcon.icns` on disk — handles manually copied resource bundles.
    /// 3. `iconImage(size: 256)` — programmatic fallback, always succeeds.
    public static func applicationIconImage() -> NSImage {
        // SwiftPM and ad-hoc builds do not always expose the bundled AppIcon asset,
        // so fall back to an in-process generated icon when needed.
        if let named = NSImage(named: "AppIcon") {
            return named
        }
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let diskIcon = NSImage(contentsOf: iconURL) {
            return diskIcon
        }
        return iconImage(size: 256)
    }

    /// Generates a square app icon at the given point size.
    ///
    /// The icon depicts three vertical panes on a blue gradient background — a visual metaphor
    /// for the window-splitting concept at the core of PanePilot. All dimensions are expressed
    /// as fractions of `size` so the result is crisp at any resolution.
    public static func iconImage(size: CGFloat) -> NSImage {
        // The generated icon mirrors the three-pane layout metaphor used by the app.
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let bounds = NSRect(x: 0, y: 0, width: size, height: size)
        let bg = NSBezierPath(roundedRect: bounds, xRadius: size * 0.2, yRadius: size * 0.2)
        let gradient = NSGradient(
            colors: [
                NSColor(calibratedRed: 0.05, green: 0.45, blue: 0.84, alpha: 1.0),
                NSColor(calibratedRed: 0.03, green: 0.31, blue: 0.67, alpha: 1.0),
            ]
        )
        gradient?.draw(in: bg, angle: 270)

        let left = NSRect(x: size * 0.14, y: size * 0.18, width: size * 0.22, height: size * 0.64)
        let middle = NSRect(x: size * 0.39, y: size * 0.18, width: size * 0.22, height: size * 0.64)
        let right = NSRect(x: size * 0.64, y: size * 0.18, width: size * 0.22, height: size * 0.64)

        NSColor.white.withAlphaComponent(0.95).setFill()
        NSColor.white.withAlphaComponent(0.42).setStroke()
        let lineWidth = max(1, size * 0.015)
        for rect in [left, middle, right] {
            let pane = NSBezierPath(roundedRect: rect, xRadius: size * 0.03, yRadius: size * 0.03)
            pane.fill()
            pane.lineWidth = lineWidth
            pane.stroke()
        }

        image.unlockFocus()
        return image
    }

    /// Generates the 18×18 pt menu bar glyph.
    ///
    /// Three vertically-aligned panes are drawn with `labelColor` and `isTemplate = true` so
    /// macOS automatically inverts the image in Dark Mode and when the menu bar background is
    /// dark. The glyph must stay simple — a template image is alpha-masked; colour fills are
    /// ignored by the system compositor.
    public static func menuBarImage() -> NSImage {
        // Menu bar glyphs must stay simple and template-friendly to match the system tint.
        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        NSColor.labelColor.setFill()
        let paneWidth = size * 0.23
        let paneHeight = size * 0.72
        let y = (size - paneHeight) / 2
        let spacing = size * 0.08
        let x0 = (size - (3 * paneWidth + 2 * spacing)) / 2

        for i in 0 ..< 3 {
            let x = x0 + CGFloat(i) * (paneWidth + spacing)
            let pane = NSBezierPath(
                roundedRect: NSRect(x: x, y: y, width: paneWidth, height: paneHeight),
                xRadius: size * 0.09,
                yRadius: size * 0.09
            )
            pane.fill()
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
