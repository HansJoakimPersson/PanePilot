import AppKit
import Foundation

/// Draws a full-screen, mouse-transparent preview overlay that highlights a single snap region.
///
/// `OverlayWindowController` manages a single borderless, opaque-clear `NSWindow` that covers
/// the active screen at `.statusBar` window level. The window ignores mouse events so drags
/// pass through it uninterrupted. The overlay is reused across drag events — only its content
/// and frame are updated, avoiding repeated window creation/destruction.
///
/// During a snap drag, `DragSnapController` calls `show(screen:layout:highlightedRegionID:)`
/// each time the hovered picker region changes, and `hide()` when the picker is dismissed.
@MainActor
final class OverlayWindowController {
    private var overlayWindow: NSWindow?
    private var overlayView: OverlayView?

    // MARK: - Presentation

    /// Shows (or updates) the overlay on `screen`, highlighting a specific region.
    ///
    /// The window is created lazily on the first call and reused on subsequent calls.
    /// If `highlightedRegionID` is `nil`, the overlay is shown with no highlighted region
    /// (a near-invisible white tint over the whole screen).
    func show(screen: NSScreen, layout: RegionLayout, highlightedRegionID: Int?) {
        let window: NSWindow
        let view: OverlayView
        let targetFrame = screen.visibleFrame.insetBy(dx: -3, dy: -3)

        if let existingWindow = overlayWindow, let existingView = overlayView {
            window = existingWindow
            view = existingView
        } else {
            view = OverlayView()
            // Reuse one borderless overlay window across drags to avoid creating and
            // destroying transient windows every time the pointer crosses a region.
            window = makeOverlayWindow(frame: targetFrame, view: view)

            overlayWindow = window
            overlayView = view
        }

        if window.frame != targetFrame {
            window.setFrame(targetFrame, display: true)
        }
        view.update(layout: layout, highlightedRegionID: highlightedRegionID)
        window.orderFrontRegardless()
    }

    func hide() {
        overlayWindow?.orderOut(nil)
    }

    private func makeOverlayWindow(frame: CGRect, view: OverlayView) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = view
        return window
    }
}

/// Custom view that draws the region highlight glow and zone number directly with CoreGraphics.
///
/// The view covers the full overlay window (which itself covers the screen). Only the
/// highlighted region is rendered with a visible fill, stroke, and number — all other regions
/// are skipped, keeping the overlay visually clean during the picker interaction.
final class OverlayView: NSView {
    private var layout: RegionLayout?
    private var highlightedRegionID: Int?

    override var isOpaque: Bool { false }

    // MARK: - State

    /// Updates the overlay's highlighted region and triggers a redraw.
    func update(layout: RegionLayout, highlightedRegionID: Int?) {
        self.layout = layout
        self.highlightedRegionID = highlightedRegionID
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let layout else {
            return
        }

        context.clear(bounds)
        NSColor.white.withAlphaComponent(0.03).setFill()
        bounds.fill()

        for region in layout.regions {
            let rect = denormalizedRect(region.normalizedFrame, in: bounds)
            guard region.id == highlightedRegionID else { continue }

            let roundedRect = rect.insetBy(dx: 4, dy: 4)
            let path = NSBezierPath(roundedRect: roundedRect, xRadius: 24, yRadius: 24)

            NSColor.white.withAlphaComponent(0.16).setFill()
            path.fill()

            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: -1),
                blur: 10,
                color: NSColor.black.withAlphaComponent(0.35).cgColor
            )
            NSColor.white.withAlphaComponent(0.96).setStroke()
            path.lineWidth = 3
            path.stroke()
            context.restoreGState()

            // Draw the zone number centred in the highlighted region.
            let label = "\(region.id)" as NSString
            let fontSize = max(24, min(roundedRect.height / 3.5, roundedRect.width / 2.5, 72))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            ]
            let textSize = label.size(withAttributes: attrs)
            let textOrigin = CGPoint(
                x: roundedRect.midX - textSize.width / 2,
                y: roundedRect.midY - textSize.height / 2
            )

            // Subtle shadow behind the number for legibility.
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: -1),
                blur: 4,
                color: NSColor.black.withAlphaComponent(0.5).cgColor
            )
            label.draw(at: textOrigin, withAttributes: attrs)
            context.restoreGState()
        }
    }

    // MARK: - Geometry

    private func denormalizedRect(_ normalized: CGRect, in container: CGRect) -> CGRect {
        CGRect(
            x: container.minX + (container.width * normalized.minX),
            y: container.minY + (container.height * normalized.minY),
            width: container.width * normalized.width,
            height: container.height * normalized.height
        ).integral
    }
}
