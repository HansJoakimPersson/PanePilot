import AppKit
import Foundation

@MainActor
final class DragSnapController {
    private enum RegionSnapVariant: String {
        case full
        case topHalf
        case bottomHalf
    }

    private let permissions: PermissionManager
    private let screens: ScreenProvider
    private let layoutEngine: LayoutEngine
    private let windowController: WindowController
    private let overlayController = OverlayWindowController()

    private var isEnabled = true

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var mouseDownLocation: CGPoint?
    private var currentScreen: NSScreen?
    private var currentHighlightedRegionID: Int?
    private var currentSnapVariant: RegionSnapVariant = .full
    private var overlayVisible = false
    private var initialWindowSnapshot: FocusedWindowSnapshot?
    private var dragWindowConfirmed = false
    private let logger = DebugLogger.shared
    private let displayLayoutStore: DisplayLayoutStore
    private let selfPID = ProcessInfo.processInfo.processIdentifier
    private var requiresModifierKey = true
    private var requiredModifier: SnapModifier = .command

    init(
        permissions: PermissionManager,
        screens: ScreenProvider,
        layoutEngine: LayoutEngine,
        windowController: WindowController,
        displayLayoutStore: DisplayLayoutStore
    ) {
        self.permissions = permissions
        self.screens = screens
        self.layoutEngine = layoutEngine
        self.windowController = windowController
        self.displayLayoutStore = displayLayoutStore
    }

    func start() {
        logger.info("DragSnapController started. Log file: \(logger.logFileURL.path)")
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp],
            handler: { [weak self] event in
                DispatchQueue.main.async { [weak self] in
                    self?.handle(event: event)
                }
            }
        )
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp],
            handler: { [weak self] event in
                self?.handle(event: event)
                return event
            }
        )
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        logger.info("Snapping \(enabled ? "enabled" : "disabled")")
        if !enabled {
            resetOverlay()
        }
    }

    func setRequiresModifierKey(_ required: Bool) {
        requiresModifierKey = required
        logger.info("Modifier requirement \(required ? "enabled (hold \(requiredModifier.displayName))" : "disabled")")
        if !required {
            return
        }
        // If user turns it on while dragging without modifier, drop overlay immediately.
        if !isModifierActive() {
            resetOverlay()
        }
    }

    func setRequiredModifier(_ modifier: SnapModifier) {
        requiredModifier = modifier
        logger.info("Snap modifier changed to \(modifier.displayName)")
        if requiresModifierKey, !isModifierActive() {
            resetOverlay()
        }
    }

    private func handle(event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let mousePoint = NSEvent.mouseLocation
            mouseDownLocation = mousePoint
            currentHighlightedRegionID = nil
            currentSnapVariant = .full
            overlayVisible = false
            dragWindowConfirmed = false
            initialWindowSnapshot = windowController.snapshotWindowForDrag(at: mousePoint)
        case .leftMouseDragged:
            handleDragged()
        case .leftMouseUp:
            handleMouseUp()
        default:
            break
        }
    }

    private func handleDragged() {
        guard isEnabled else { return }
        guard isModifierActive() else {
            if overlayVisible {
                resetOverlay()
            }
            return
        }
        guard permissions.ensureAccessibilityPermission(prompt: false) else { return }
        guard let down = mouseDownLocation else { return }
        guard let initialSnapshot = initialWindowSnapshot else { return }
        guard shouldConsiderWindow(initialSnapshot) else { return }

        let location = NSEvent.mouseLocation
        let distance = hypot(location.x - down.x, location.y - down.y)
        guard distance >= 16 else { return }

        guard let currentSnapshot = windowController.snapshotWindowForDrag(at: location) else { return }
        guard shouldConsiderWindow(currentSnapshot) else { return }
        guard isSameWindow(initialSnapshot, currentSnapshot) else { return }

        // Only activate snapping overlay when the actual window has started moving.
        let movedDistance = hypot(
            currentSnapshot.frame.origin.x - initialSnapshot.frame.origin.x,
            currentSnapshot.frame.origin.y - initialSnapshot.frame.origin.y
        )
        guard movedDistance >= 4 else { return }
        dragWindowConfirmed = true

        guard let screen = screen(at: location) else { return }
        let layout = displayLayoutStore.layout(for: screen)
        currentScreen = screen

        let highlighted = region(at: location, on: screen, layout: layout)
        let snapVariant = highlighted.map { snapVariantForPoint(location, region: $0, on: screen) } ?? RegionSnapVariant.full
        if let highlighted, highlighted.id != currentHighlightedRegionID {
            logger.info("Drag hover region=\(highlighted.id) layout=\(layout.id)")
        }
        currentHighlightedRegionID = highlighted?.id
        currentSnapVariant = snapVariant
        overlayController.show(
            screen: screen,
            layout: layout,
            highlightedRegionID: highlighted?.id,
            highlightedVariant: overlayVariant(for: snapVariant)
        )
        overlayVisible = true
    }

    private func handleMouseUp() {
        defer { resetOverlay() }

        guard isEnabled, overlayVisible, dragWindowConfirmed else { return }
        guard isModifierActive() else {
            logger.info("Snap canceled: modifier key not active at drop.")
            return
        }
        guard permissions.ensureAccessibilityPermission(prompt: false) else {
            logger.warn("Snap aborted: accessibility permission missing.")
            return
        }
        guard let screen = currentScreen else { return }
        let location = NSEvent.mouseLocation
        guard let snapshot = windowController.snapshotWindowForDrag(at: location) ?? initialWindowSnapshot else {
            logger.warn("Snap aborted: no draggable window found at drop.")
            return
        }
        guard shouldConsiderWindow(snapshot) else {
            logger.info("Snap canceled: filtered window app=\(snapshot.appName) pid=\(snapshot.pid) role=\(snapshot.role)/\(snapshot.subrole)")
            return
        }
        guard snapshot.positionSettable, snapshot.sizeSettable else {
            logger.warn(
                "Snap aborted: window not settable app=\(snapshot.appName) role=\(snapshot.role)/\(snapshot.subrole) " +
                "settable(pos=\(snapshot.positionSettable),size=\(snapshot.sizeSettable))"
            )
            return
        }
        let layout = displayLayoutStore.layout(for: screen)
        guard let region = region(at: location, on: screen, layout: layout) else {
            logger.info("Snap canceled: mouse released outside snappable region.")
            return
        }
        let snapVariant = snapVariantForPoint(location, region: region, on: screen)

        let baseFrame = layoutEngine.frame(for: snapVisibleFrame(for: screen), region: region)
        let targetFrame = targetFrame(for: baseFrame, variant: snapVariant)
        do {
            var info = try windowController.moveWindow(snapshot, to: targetFrame)

            let widthDelta = abs(info.finalFrame.width - info.requestedFrame.width)
            let heightDelta = abs(info.finalFrame.height - info.requestedFrame.height)
            if widthDelta > 1 || heightDelta > 1 {
                let correctedOrigin = correctedOrigin(
                    for: region,
                    variant: snapVariant,
                    requestedFrame: info.requestedFrame,
                    actualSize: info.finalFrame.size
                )
                try windowController.setWindowPosition(snapshot, to: correctedOrigin)
                info = try windowController.moveWindow(snapshot, to: CGRect(origin: correctedOrigin, size: info.finalFrame.size))
                logger.warn(
                    """
                    Snap constrained by app min size: app=\(info.appName) bundle=\(info.bundleID) \
                    requested=\(targetFrame.debugDescription) actual=\(info.finalFrame.debugDescription) \
                    reappliedOrigin=\(correctedOrigin.debugDescription)
                    """
                )
            }

            logger.info(
                """
                Snap success: app=\(info.appName) bundle=\(info.bundleID) pid=\(info.pid) \
                title=\"\(info.windowTitle)\" role=\(info.role)/\(info.subrole) \
                minimized=\(info.minimized) settable(pos=\(info.positionSettable),size=\(info.sizeSettable)) \
                layout=\(layout.id) region=\(region.id) variant=\(snapVariant.rawValue) requested=\(info.requestedFrame.debugDescription) final=\(info.finalFrame.debugDescription)
                """
            )
        } catch {
            logger.error(
                """
                Snap failure: layout=\(layout.id) region=\(region.id) frame=\(targetFrame.debugDescription) \
                error=\"\(error.localizedDescription)\"
                """
            )
        }
    }

    private func resetOverlay() {
        overlayController.hide()
        mouseDownLocation = nil
        currentScreen = nil
        currentHighlightedRegionID = nil
        currentSnapVariant = .full
        overlayVisible = false
        initialWindowSnapshot = nil
        dragWindowConfirmed = false
    }

    private func screen(at point: CGPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(point) })
    }

    private func region(at point: CGPoint, on screen: NSScreen, layout: RegionLayout) -> RegionLayout.Region? {
        for region in layout.regions {
            let rect = layoutEngine.frame(for: snapVisibleFrame(for: screen), region: region)
            if rect.contains(point) {
                return region
            }
        }
        return nil
    }

    private func isSameWindow(_ lhs: FocusedWindowSnapshot, _ rhs: FocusedWindowSnapshot) -> Bool {
        guard lhs.pid == rhs.pid, lhs.role == rhs.role, lhs.subrole == rhs.subrole else {
            return false
        }
        // Some apps change title dynamically while dragging.
        if lhs.windowTitle == rhs.windowTitle {
            return true
        }
        return abs(lhs.frame.width - rhs.frame.width) < 2 && abs(lhs.frame.height - rhs.frame.height) < 2
    }

    private func shouldConsiderWindow(_ snapshot: FocusedWindowSnapshot) -> Bool {
        // Never snap this app's own windows (settings, future editors, etc).
        if snapshot.pid == selfPID {
            return false
        }

        // Dialog sheets are often non-resizable and produce noisy false positives.
        if snapshot.subrole == "AXDialog" || snapshot.role == "AXSheet" {
            return false
        }

        // If size isn't settable, skip early to avoid showing overlay when it cannot snap.
        if !snapshot.sizeSettable {
            return false
        }

        return true
    }

    private func correctedOrigin(
        for region: RegionLayout.Region,
        variant: RegionSnapVariant,
        requestedFrame: CGRect,
        actualSize: CGSize
    ) -> CGPoint {
        let horizontalAnchor: CGFloat
        let epsilon = 0.0001
        if region.normalizedFrame.minX <= epsilon {
            horizontalAnchor = requestedFrame.minX // left
        } else if region.normalizedFrame.maxX >= (1.0 - epsilon) {
            horizontalAnchor = requestedFrame.maxX - actualSize.width // right
        } else {
            horizontalAnchor = requestedFrame.midX - (actualSize.width / 2.0) // center
        }

        let verticalAnchor: CGFloat
        if variant == .bottomHalf {
            verticalAnchor = requestedFrame.minY // bottom half always anchors bottom
        } else if variant == .topHalf {
            verticalAnchor = requestedFrame.maxY - actualSize.height // top half always anchors top
        } else if region.normalizedFrame.minY <= epsilon {
            verticalAnchor = requestedFrame.minY // bottom
        } else if region.normalizedFrame.maxY >= (1.0 - epsilon) {
            verticalAnchor = requestedFrame.maxY - actualSize.height // top
        } else {
            verticalAnchor = requestedFrame.midY - (actualSize.height / 2.0) // center
        }

        return CGPoint(x: horizontalAnchor, y: verticalAnchor)
    }

    private func isModifierActive() -> Bool {
        if !requiresModifierKey {
            return true
        }
        return NSEvent.modifierFlags.contains(requiredModifier.eventFlag)
    }

    private func snapVisibleFrame(for screen: NSScreen) -> CGRect {
        screen.visibleFrame.insetBy(dx: -3, dy: -3)
    }

    private func snapVariantForPoint(_ point: CGPoint, region: RegionLayout.Region, on screen: NSScreen) -> RegionSnapVariant {
        let frame = layoutEngine.frame(for: snapVisibleFrame(for: screen), region: region)
        guard frame.height > 40 else { return .full }
        let topZoneThreshold = frame.minY + (frame.height * 0.70)
        let bottomZoneThreshold = frame.minY + (frame.height * 0.30)
        if point.y >= topZoneThreshold {
            return .topHalf
        }
        if point.y <= bottomZoneThreshold {
            return .bottomHalf
        }
        return .full
    }

    private func targetFrame(for baseFrame: CGRect, variant: RegionSnapVariant) -> CGRect {
        switch variant {
        case .full:
            return baseFrame
        case .topHalf:
            let halfHeight = (baseFrame.height / 2.0).rounded(.down)
            return CGRect(
                x: baseFrame.minX,
                y: baseFrame.maxY - halfHeight,
                width: baseFrame.width,
                height: halfHeight
            ).integral
        case .bottomHalf:
            let halfHeight = (baseFrame.height / 2.0).rounded(.down)
            return CGRect(
                x: baseFrame.minX,
                y: baseFrame.minY,
                width: baseFrame.width,
                height: halfHeight
            ).integral
        }
    }
    private func overlayVariant(for variant: RegionSnapVariant) -> OverlayHighlightVariant {
        switch variant {
        case .full: .full
        case .topHalf: .topHalf
        case .bottomHalf: .bottomHalf
        }
    }
}
