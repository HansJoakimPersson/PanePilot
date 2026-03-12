import AppKit
import Foundation

enum OverlayHighlightVariant {
    case full
    case topHalf
    case bottomHalf
}

@MainActor
final class OverlayWindowController {
    private var overlayWindow: NSWindow?
    private var overlayView: OverlayView?

    func show(screen: NSScreen, layout: RegionLayout, highlightedRegionID: Int?, highlightedVariant: OverlayHighlightVariant) {
        let window: NSWindow
        let view: OverlayView
        let targetFrame = screen.visibleFrame.insetBy(dx: -3, dy: -3)

        if let existingWindow = overlayWindow, let existingView = overlayView {
            window = existingWindow
            view = existingView
        } else {
            view = OverlayView()
            window = NSWindow(
                contentRect: targetFrame,
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

            overlayWindow = window
            overlayView = view
        }

        if window.frame != targetFrame {
            window.setFrame(targetFrame, display: true)
        }
        view.update(layout: layout, highlightedRegionID: highlightedRegionID, highlightedVariant: highlightedVariant)
        window.orderFrontRegardless()
    }

    func hide() {
        overlayWindow?.orderOut(nil)
    }
}

final class OverlayView: NSView {
    private var layout: RegionLayout?
    private var highlightedRegionID: Int?
    private var highlightedVariant: OverlayHighlightVariant = .full

    override var isOpaque: Bool { false }

    func update(layout: RegionLayout, highlightedRegionID: Int?, highlightedVariant: OverlayHighlightVariant) {
        self.layout = layout
        self.highlightedRegionID = highlightedRegionID
        self.highlightedVariant = highlightedVariant
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let layout else {
            return
        }

        context.clear(bounds)
        NSColor.white.withAlphaComponent(0.03).setFill()
        bounds.fill()

        for region in layout.regions {
            let rect = denormalizedRect(region.normalizedFrame, in: bounds)
            let isHighlighted = (region.id == highlightedRegionID)
            guard isHighlighted else { continue }
            let highlightRect = highlightedRect(in: rect, variant: highlightedVariant)
            let roundedRect = highlightRect.insetBy(dx: 4, dy: 4)
            let path = NSBezierPath(roundedRect: roundedRect, xRadius: 24, yRadius: 24)

            let fillColor: NSColor = isHighlighted
                ? NSColor.white.withAlphaComponent(0.16)
                : NSColor.white.withAlphaComponent(0.08)
            fillColor.setFill()
            path.fill()

            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: -1),
                blur: isHighlighted ? 10 : 6,
                color: NSColor.black.withAlphaComponent(isHighlighted ? 0.35 : 0.2).cgColor
            )
            NSColor.white.withAlphaComponent(isHighlighted ? 0.96 : 0.82).setStroke()
            path.lineWidth = 3
            path.stroke()
            context.restoreGState()

            drawLabel(
                text: "\(region.id)",
                in: roundedRect,
                highlighted: isHighlighted
            )
        }
    }

    private func denormalizedRect(_ normalized: CGRect, in container: CGRect) -> CGRect {
        CGRect(
            x: container.minX + (container.width * normalized.minX),
            y: container.minY + (container.height * normalized.minY),
            width: container.width * normalized.width,
            height: container.height * normalized.height
        ).integral
    }

    private func highlightedRect(in regionRect: CGRect, variant: OverlayHighlightVariant) -> CGRect {
        switch variant {
        case .full:
            return regionRect
        case .topHalf:
            let halfHeight = floor(regionRect.height / 2.0)
            return CGRect(
                x: regionRect.minX,
                y: regionRect.maxY - halfHeight,
                width: regionRect.width,
                height: halfHeight
            ).integral
        case .bottomHalf:
            let halfHeight = floor(regionRect.height / 2.0)
            return CGRect(
                x: regionRect.minX,
                y: regionRect.minY,
                width: regionRect.width,
                height: halfHeight
            ).integral
        }
    }

    private func drawLabel(text: String, in rect: CGRect, highlighted: Bool) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: highlighted ? 42 : 32),
            .foregroundColor: NSColor.white.withAlphaComponent(highlighted ? 0.95 : 0.75),
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        let point = CGPoint(
            x: rect.midX - (size.width / 2),
            y: rect.midY - (size.height / 2)
        )
        attributed.draw(at: point)
    }
}
