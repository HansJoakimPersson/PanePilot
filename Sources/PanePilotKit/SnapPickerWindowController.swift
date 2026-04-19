import AppKit
import Foundation

// MARK: - Controller

/// Presents the Windows Snap Assist–style layout picker during a modifier+drag or keyboard
/// snap interaction.
///
/// `SnapPickerWindowController` manages a borderless, mouse-transparent `NSPanel` that appears
/// at the top-centre of the active screen. The panel displays all available layouts as
/// proportional thumbnails in a horizontal row. Each thumbnail shows:
/// - A **layout index badge** (1, 2, 3…) for keyboard navigation.
/// - A **zone number** centred in every region for keyboard navigation.
///
/// **Window properties:**
/// - Level `.floating` — renders above normal windows; the picker must be visible during drag.
/// - `ignoresMouseEvents = true` — drag events pass through the picker uninterrupted.
/// - `NSVisualEffectView` with `.menu` material and `alphaValue = 1.0` for an opaque frosted background.
/// - `canJoinAllSpaces` + `fullScreenAuxiliary` so the picker follows the cursor across Spaces.
///
/// **Key methods called by `DragSnapController`:**
/// - `show(layouts:on:)` — creates or repositions the panel and populates thumbnails.
/// - `hide()` — removes the panel from screen.
/// - `hitTest(at:)` — converts a global screen point to a `(layout, region)` pair.
/// - `setHoveredRegion(layoutID:regionID:)` — highlights a region in the matching thumbnail.
@MainActor
final class SnapPickerWindowController {
    private var panel: NSPanel?
    private var pickerView: SnapPickerView?
    private var currentLayouts: [RegionLayout] = []

    // MARK: - Presentation

    /// Shows the picker on `screen`, populating it with `layouts`.
    ///
    /// If the panel already exists it is repositioned and its content replaced; otherwise a
    /// new panel is created. The panel is placed just below the menu bar, horizontally centred.
    func show(layouts: [RegionLayout], on screen: NSScreen) {
        currentLayouts = layouts

        let picker: SnapPickerView
        let win: NSPanel

        if let existingPanel = panel, let existingView = pickerView {
            win = existingPanel
            picker = existingView
        } else {
            picker = SnapPickerView(frame: .zero)
            win = makePanel(view: picker)
            panel = win
            pickerView = picker
        }

        picker.setLayouts(layouts, screenAspectRatio: screen.frame.width / screen.frame.height)

        let panelSize = picker.fittingSize
        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.midX - panelSize.width / 2
        let y = visibleFrame.maxY - panelSize.height - 12
        win.setFrame(CGRect(origin: CGPoint(x: x, y: y), size: panelSize), display: true)
        win.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        pickerView?.clearHover()
    }

    // MARK: - Hit Testing

    /// Returns the layout and region under the given global (screen) point, or nil.
    func hitTest(at globalPoint: CGPoint) -> (layout: RegionLayout, region: RegionLayout.Region)? {
        guard let win = panel, let picker = pickerView, win.isVisible else { return nil }
        // Convert from global AppKit coordinates to window coordinates, then to view coordinates.
        let windowPoint = win.convertPoint(fromScreen: globalPoint)
        let viewPoint = picker.convert(windowPoint, from: nil)
        return picker.hitTest(at: viewPoint)
    }

    func setHoveredRegion(layoutID: String?, regionID: Int?) {
        pickerView?.setHover(layoutID: layoutID, regionID: regionID)
    }

    // MARK: - Window Setup

    private func makePanel(view: SnapPickerView) -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // .floating keeps the picker visible above regular app windows during drag.
        // The picker must be visible so the user can see the layout zones — unlike Windows 11
        // Snap Assist there is no drag thumbnail, so the picker being above the dragged window
        // is the intended behaviour.
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = view
        return panel
    }
}

// MARK: - Picker View

private final class SnapPickerView: NSView {
    private var cards: [LayoutCardView] = []
    private var stackView: NSStackView?

    // MARK: - Layout

    func setLayouts(_ layouts: [RegionLayout], screenAspectRatio: CGFloat) {
        for card in cards { card.removeFromSuperview() }
        cards = []
        stackView?.removeFromSuperview()
        stackView = nil

        let thumbnailHeight: CGFloat = 72
        let thumbnailWidth = (thumbnailHeight * screenAspectRatio).rounded()
        // Pass the 1-based layout index so thumbnails can display keyboard-navigation numbers.
        let cardViews = layouts.enumerated().map { (index, layout) in
            LayoutCardView(
                layout: layout,
                layoutIndex: index + 1,
                thumbnailSize: CGSize(width: thumbnailWidth, height: thumbnailHeight)
            )
        }
        cards = cardViews

        let stack = NSStackView(views: cardViews)
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stackView = stack

        // Visual effect background
        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.alphaValue = 1.0
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.translatesAutoresizingMaskIntoConstraints = false

        subviews.forEach { $0.removeFromSuperview() }
        addSubview(effect)
        effect.addSubview(stack)

        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: trailingAnchor),
            effect.topAnchor.constraint(equalTo: topAnchor),
            effect.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        needsLayout = true
    }

    override var intrinsicContentSize: CGSize {
        guard let stack = stackView else { return CGSize(width: 400, height: 120) }
        let fit = stack.fittingSize
        return CGSize(width: max(fit.width, 300), height: max(fit.height, 100))
    }

    // MARK: - Hover

    func setHover(layoutID: String?, regionID: Int?) {
        for card in cards {
            card.setHover(regionID: card.layout.id == layoutID ? regionID : nil)
        }
    }

    func clearHover() {
        for card in cards { card.setHover(regionID: nil) }
    }

    // MARK: - Hit Testing

    func hitTest(at viewPoint: CGPoint) -> (layout: RegionLayout, region: RegionLayout.Region)? {
        for card in cards {
            let cardPoint = card.convert(viewPoint, from: self)
            if card.bounds.contains(cardPoint) {
                if let regionID = card.thumbnailHitTest(at: cardPoint) {
                    if let region = card.layout.regions.first(where: { $0.id == regionID }) {
                        return (card.layout, region)
                    }
                }
            }
        }
        return nil
    }
}

// MARK: - Layout Card

private final class LayoutCardView: NSView {
    let layout: RegionLayout
    private let thumbnail: LayoutThumbnailView

    init(layout: RegionLayout, layoutIndex: Int, thumbnailSize: CGSize) {
        self.layout = layout
        self.thumbnail = LayoutThumbnailView(layout: layout, layoutIndex: layoutIndex, size: thumbnailSize)
        super.init(frame: .zero)

        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbnail)

        NSLayoutConstraint.activate([
            thumbnail.topAnchor.constraint(equalTo: topAnchor),
            thumbnail.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnail.trailingAnchor.constraint(equalTo: trailingAnchor),
            thumbnail.bottomAnchor.constraint(equalTo: bottomAnchor),
            thumbnail.widthAnchor.constraint(equalToConstant: thumbnailSize.width),
            thumbnail.heightAnchor.constraint(equalToConstant: thumbnailSize.height),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setHover(regionID: Int?) {
        thumbnail.setHover(regionID: regionID)
    }

    /// Returns the region ID under the given point (in this view's coordinate space), or nil.
    func thumbnailHitTest(at pointInCard: CGPoint) -> Int? {
        let thumbPoint = thumbnail.convert(pointInCard, from: self)
        return thumbnail.hitTest(at: thumbPoint)
    }
}

// MARK: - Thumbnail View

private final class LayoutThumbnailView: NSView {
    private let layout: RegionLayout
    /// 1-based position of this layout in the picker row, shown as a keyboard-navigation badge.
    private let layoutIndex: Int
    private var hoveredRegionID: Int?

    init(layout: RegionLayout, layoutIndex: Int, size: CGSize) {
        self.layout = layout
        self.layoutIndex = layoutIndex
        super.init(frame: CGRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }

    func setHover(regionID: Int?) {
        guard hoveredRegionID != regionID else { return }
        hoveredRegionID = regionID
        needsDisplay = true
    }

    func hitTest(at point: CGPoint) -> Int? {
        guard bounds.contains(point) else { return nil }
        for region in layout.regions {
            let rect = denormalized(region.normalizedFrame, in: bounds)
            if rect.contains(point) { return region.id }
        }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)

        // Background
        NSColor.windowBackgroundColor.withAlphaComponent(0.3).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()

        // Regions: fill + stroke + zone number
        for region in layout.regions {
            let rect = denormalized(region.normalizedFrame, in: bounds).insetBy(dx: 1, dy: 1)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5)
            let isHovered = region.id == hoveredRegionID

            if isHovered {
                NSColor.controlAccentColor.withAlphaComponent(0.55).setFill()
            } else {
                NSColor.labelColor.withAlphaComponent(0.12).setFill()
            }
            path.fill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 0.5
            path.stroke()

            // Zone number centred in the region.
            let zoneLabel = "\(region.id)" as NSString
            let zoneFontSize = max(7, min(rect.height / 2.8, rect.width / 1.8, 16))
            let zoneAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: zoneFontSize, weight: .semibold),
                .foregroundColor: isHovered
                    ? NSColor.white.withAlphaComponent(0.9)
                    : NSColor.labelColor.withAlphaComponent(0.45),
            ]
            let zoneSize = zoneLabel.size(withAttributes: zoneAttrs)
            zoneLabel.draw(
                at: CGPoint(x: rect.midX - zoneSize.width / 2, y: rect.midY - zoneSize.height / 2),
                withAttributes: zoneAttrs
            )
        }

        // Layout index badge — small rounded pill in the top-left corner.
        // In AppKit's bottom-left coordinate system "top-left" = (small x, near bounds.maxY).
        let badgeLabel = "\(layoutIndex)" as NSString
        let badgeFontSize: CGFloat = 7.5
        let badgeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: badgeFontSize, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let badgeTextSize = badgeLabel.size(withAttributes: badgeAttrs)
        let badgePad: CGFloat = 2.5
        let badgeW = badgeTextSize.width + badgePad * 2
        let badgeH = badgeTextSize.height + badgePad * 2
        let badgeRect = CGRect(x: 3, y: bounds.maxY - badgeH - 3, width: badgeW, height: badgeH)
        NSColor.black.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 2, yRadius: 2).fill()
        badgeLabel.draw(
            at: CGPoint(x: badgeRect.minX + badgePad, y: badgeRect.minY + badgePad),
            withAttributes: badgeAttrs
        )
    }

    private func denormalized(_ normalized: CGRect, in container: CGRect) -> CGRect {
        CGRect(
            x: container.minX + container.width * normalized.minX,
            y: container.minY + container.height * normalized.minY,
            width: container.width * normalized.width,
            height: container.height * normalized.height
        ).integral
    }
}
