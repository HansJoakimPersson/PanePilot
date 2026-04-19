import AppKit
import Foundation

/// Observes global mouse and keyboard events and drives the full snap interaction lifecycle.
///
/// **Drag snap flow** (modifier + drag):
/// 1. Detects the drag by comparing mouse-down and mouse-moved positions.
/// 2. Confirms that the dragged object is a resizable, non-PanePilot window.
/// 3. Shows `SnapPickerWindowController` at the top of the active screen.
/// 4. Hit-tests the picker on every drag event and shows a preview overlay via `OverlayWindowController`.
/// 5. On mouse-up, if a picker region is hovered, moves and resizes the window to match.
///
/// **Keyboard snap flow** (modifier + trigger key, then layout# + zone#):
/// 1. User holds the snap modifier and presses the keyboard-snap trigger key (default: Escape).
/// 2. Controller snapshots the frontmost window and shows the picker.
/// 3. User presses a layout index digit (1–9): the layout is selected.
/// 4. User presses a zone index digit (1–9): the window snaps and the picker dismisses.
/// 5. Pressing Escape at any point cancels keyboard snap mode.
///
/// All monitors must be registered *after* Accessibility is granted; call `restart()` if
/// permission arrives late.
///
/// > Note: Global `NSEvent` monitors deliver copies of events — they cannot intercept them.
/// > This means that during keyboard snap the key presses are also delivered to the frontmost
/// > application. A future implementation could use `CGEventTap` to suppress them.
@MainActor
final class DragSnapController {
    private let permissions: PermissionManager
    private let screens: ScreenProvider
    private let layoutEngine: LayoutEngine
    private let windowController: WindowController
    private let snapPickerController = SnapPickerWindowController()
    private let previewOverlayController = OverlayWindowController()

    private var isEnabled = true

    // MARK: Drag snap state
    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// Screen-space point where the left mouse button was pressed.
    private var mouseDownLocation: CGPoint?
    /// The screen that contained the cursor when the picker was last shown.
    private var currentScreen: NSScreen?
    private var pickerVisible = false
    /// AX snapshot taken at mouse-down, used to identify the target window.
    private var initialWindowSnapshot: FocusedWindowSnapshot?
    /// `true` once the tracked window's frame has actually moved ≥ 4 pt.
    private var dragWindowConfirmed = false
    /// The layout and region currently under the cursor in the picker, or `nil` if none.
    private var hoveredSelection: (layout: RegionLayout, region: RegionLayout.Region)?

    // MARK: Keyboard snap state
    /// Keyboard event monitors (separate from the drag mouse monitors).
    private var globalKeyboardMonitor: Any?
    private var localKeyboardMonitor: Any?
    /// `true` while the picker is shown via keyboard (not drag).
    private var keyboardSnapActive = false
    /// AX snapshot of the window to snap, captured when keyboard snap mode activates.
    private var keyboardSnapSnapshot: FocusedWindowSnapshot?
    /// The screen the keyboard-snap target window lives on.
    private var keyboardSnapScreen: NSScreen?
    /// Layout index (0-based) selected by the first digit keypress, awaiting zone digit.
    private var pendingKeyboardLayoutIndex: Int?

    // MARK: Shared
    private let logger = DebugLogger.shared
    private let displayLayoutStore: DisplayLayoutStore
    private let selfPID = ProcessInfo.processInfo.processIdentifier
    private var requiresModifierKey = true
    private var requiredModifier: SnapModifier = .command

    /// Key code for the keyboard-snap trigger (default: Escape, kVK_Escape = 53).
    ///
    /// The user holds the snap modifier and presses this key to show the picker without
    /// dragging. Configurable in a future Settings release.
    private static let keyboardSnapTriggerKeyCode: UInt16 = 53 // kVK_Escape

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

    // MARK: - Lifecycle

    /// Registers all `NSEvent` monitors and begins observing drag and keyboard events.
    ///
    /// Must be called after Accessibility is granted. If permission arrives after `start()`,
    /// call `restart()` to re-register the monitors with a now-trusted process.
    func start() {
        logger.info("DragSnapController started. Log file: \(logger.logFileURL.path)")

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp],
            handler: { [weak self] event in
                DispatchQueue.main.async { [weak self] in self?.handle(event: event) }
            }
        )
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp],
            handler: { [weak self] event in self?.handle(event: event); return event }
        )

        // Separate keyboard monitors so they can be removed independently if needed.
        globalKeyboardMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .flagsChanged],
            handler: { [weak self] event in
                DispatchQueue.main.async { [weak self] in self?.handleKeyEvent(event) }
            }
        )
        localKeyboardMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged],
            handler: { [weak self] event in self?.handleKeyEvent(event); return event }
        )
    }

    /// Stops and immediately restarts all event monitors.
    ///
    /// Used by `AppDelegate` when Accessibility permission is granted after the initial
    /// `start()` call — old monitors registered before the grant do not receive events.
    func restart() {
        stop()
        start()
        logger.info("DragSnapController restarted.")
    }

    /// Removes all event monitors.
    func stop() {
        [globalMonitor, localMonitor, globalKeyboardMonitor, localKeyboardMonitor]
            .compactMap { $0 }
            .forEach { NSEvent.removeMonitor($0) }
        globalMonitor = nil
        localMonitor = nil
        globalKeyboardMonitor = nil
        localKeyboardMonitor = nil
    }

    // MARK: - Configuration

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        logger.info("Snapping \(enabled ? "enabled" : "disabled")")
        if !enabled { resetPicker() }
    }

    func setRequiresModifierKey(_ required: Bool) {
        requiresModifierKey = required
        logger.info("Modifier requirement \(required ? "enabled (hold \(requiredModifier.displayName))" : "disabled")")
        if required, !isModifierActive() { resetPicker() }
    }

    func setRequiredModifier(_ modifier: SnapModifier) {
        requiredModifier = modifier
        logger.info("Snap modifier changed to \(modifier.displayName)")
        if requiresModifierKey, !isModifierActive() { resetPicker() }
    }

    // MARK: - Mouse Event Handling

    private func handle(event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            // Cancel keyboard snap if a drag begins.
            if keyboardSnapActive { cancelKeyboardSnap() }
            beginTrackingDrag(at: NSEvent.mouseLocation)
        case .leftMouseDragged:
            handleDragged()
        case .leftMouseUp:
            handleMouseUp()
        default:
            break
        }
    }

    private func beginTrackingDrag(at point: CGPoint) {
        mouseDownLocation = point
        hoveredSelection = nil
        pickerVisible = false
        dragWindowConfirmed = false
        initialWindowSnapshot = windowController.snapshotWindowForDrag(at: point)
    }

    private func handleDragged() {
        guard isEnabled else { return }
        guard isModifierActive() else {
            if pickerVisible { resetPicker() }
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

        // The user may click a title bar without dragging. Only show the picker after
        // the tracked window frame actually starts moving.
        let movedDistance = hypot(
            currentSnapshot.frame.origin.x - initialSnapshot.frame.origin.x,
            currentSnapshot.frame.origin.y - initialSnapshot.frame.origin.y
        )
        guard movedDistance >= 4 else { return }
        dragWindowConfirmed = true

        guard let screen = screen(at: location) else { return }

        // Show or reposition the picker when the active screen changes.
        if !pickerVisible || screen !== currentScreen {
            currentScreen = screen
            snapPickerController.show(layouts: displayLayoutStore.orderedLayouts(), on: screen)
            pickerVisible = true
            logger.info("Snap picker shown on screen \(screen.localizedName)")
        }

        // Determine what the cursor is hovering in the picker.
        let hit = snapPickerController.hitTest(at: location)
        let newLayoutID = hit?.layout.id
        let newRegionID = hit?.region.id

        let selectionChanged = newLayoutID != hoveredSelection?.layout.id
            || newRegionID != hoveredSelection?.region.id
        hoveredSelection = hit

        if selectionChanged {
            snapPickerController.setHoveredRegion(layoutID: newLayoutID, regionID: newRegionID)
            if let (layout, region) = hit {
                previewOverlayController.show(screen: screen, layout: layout, highlightedRegionID: region.id)
                logger.info("Picker hover layout=\(layout.id) region=\(region.id)")
            } else {
                previewOverlayController.hide()
            }
        }
    }

    private func handleMouseUp() {
        defer { resetPicker() }

        guard isEnabled, pickerVisible, dragWindowConfirmed else { return }
        guard isModifierActive() else {
            logger.info("Snap canceled: modifier key not active at drop.")
            return
        }
        guard permissions.ensureAccessibilityPermission(prompt: false) else {
            logger.warn("Snap aborted: accessibility permission missing.")
            return
        }
        guard let (layout, region) = hoveredSelection else {
            logger.info("Snap canceled: mouse released without hovering a picker zone.")
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

        do {
            try applySnap(snapshot: snapshot, to: region, on: screen, layout: layout)
        } catch {
            let targetFrame = layoutEngine.frame(for: snapVisibleFrame(for: screen), region: region)
            logger.error(
                "Snap failure: layout=\(layout.id) region=\(region.id) frame=\(targetFrame.debugDescription) " +
                "error=\"\(error.localizedDescription)\""
            )
        }
    }

    // MARK: - Keyboard Event Handling

    private func handleKeyEvent(_ event: NSEvent) {
        if event.type == .flagsChanged {
            // Keyboard snap mode does NOT auto-cancel on modifier release — the user releases
            // the modifier and then types the layout/zone digits.
            return
        }
        guard event.type == .keyDown else { return }

        let keyCode = event.keyCode

        if !keyboardSnapActive {
            // Check for modifier + trigger key to activate keyboard snap mode.
            if requiresModifierKey,
               isModifierActive(),
               keyCode == Self.keyboardSnapTriggerKeyCode {
                activateKeyboardSnap()
            }
        } else {
            // Escape cancels keyboard snap mode.
            if keyCode == 53 { // kVK_Escape
                cancelKeyboardSnap()
                return
            }
            if let digit = snapDigit(from: keyCode) {
                handleKeyboardSnapDigit(digit)
            }
        }
    }

    /// Activates keyboard snap mode by snapshotting the frontmost window and showing the picker.
    private func activateKeyboardSnap() {
        guard isEnabled else { return }
        guard permissions.ensureAccessibilityPermission(prompt: false) else { return }

        guard let snapshot = windowController.snapshotFocusedWindow(),
              shouldConsiderWindow(snapshot),
              snapshot.positionSettable, snapshot.sizeSettable else {
            logger.info("Keyboard snap: no eligible frontmost window.")
            return
        }

        guard let screen = screenForWindow(snapshot) else { return }

        keyboardSnapActive = true
        keyboardSnapSnapshot = snapshot
        keyboardSnapScreen = screen
        pendingKeyboardLayoutIndex = nil

        snapPickerController.show(layouts: displayLayoutStore.orderedLayouts(), on: screen)
        logger.info("Keyboard snap activated for '\(snapshot.windowTitle)'")
    }

    /// Handles a digit (1–9) pressed during keyboard snap mode.
    ///
    /// First digit selects a layout (1-based picker order); second digit selects a zone
    /// within that layout and immediately snaps the window.
    private func handleKeyboardSnapDigit(_ digit: Int) {
        let layouts = displayLayoutStore.orderedLayouts()

        if pendingKeyboardLayoutIndex == nil {
            // First digit: pick a layout.
            let index = digit - 1
            guard index < layouts.count else {
                logger.info("Keyboard snap: layout index \(digit) out of range (count: \(layouts.count)).")
                cancelKeyboardSnap()
                return
            }
            pendingKeyboardLayoutIndex = index
            let layout = layouts[index]
            logger.info("Keyboard snap: layout \(digit) '\(layout.name)' selected, awaiting zone.")

            // Preview first zone of the selected layout so the user gets visual feedback.
            if let firstRegion = layout.regions.first, let screen = keyboardSnapScreen {
                snapPickerController.setHoveredRegion(layoutID: layout.id, regionID: firstRegion.id)
                previewOverlayController.show(screen: screen, layout: layout, highlightedRegionID: firstRegion.id)
            }

        } else {
            // Second digit: pick a zone and snap.
            let layoutIndex = pendingKeyboardLayoutIndex!
            let layout = layouts[layoutIndex]
            let regionIndex = digit - 1
            guard regionIndex < layout.regions.count else {
                logger.info("Keyboard snap: zone index \(digit) out of range for layout '\(layout.name)'.")
                cancelKeyboardSnap()
                return
            }
            let region = layout.regions[regionIndex]

            guard let snapshot = keyboardSnapSnapshot,
                  let screen = keyboardSnapScreen else {
                cancelKeyboardSnap()
                return
            }

            do {
                try applySnap(snapshot: snapshot, to: region, on: screen, layout: layout)
            } catch {
                logger.error("Keyboard snap failure: layout=\(layout.id) region=\(region.id) error=\(error.localizedDescription)")
            }
            cancelKeyboardSnap()
        }
    }

    private func cancelKeyboardSnap() {
        keyboardSnapActive = false
        keyboardSnapSnapshot = nil
        keyboardSnapScreen = nil
        pendingKeyboardLayoutIndex = nil
        snapPickerController.hide()
        previewOverlayController.hide()
        logger.info("Keyboard snap cancelled.")
    }

    /// Returns the `NSScreen` that contains the centre of the given window.
    private func screenForWindow(_ snapshot: FocusedWindowSnapshot) -> NSScreen? {
        screen(at: CGPoint(x: snapshot.frame.midX, y: snapshot.frame.midY))
    }

    /// Maps ANSI and numpad key codes 1–9 to their integer values.
    private func snapDigit(from keyCode: UInt16) -> Int? {
        switch keyCode {
        // ANSI top row
        case 18: return 1
        case 19: return 2
        case 20: return 3
        case 21: return 4
        case 23: return 5
        case 22: return 6
        case 26: return 7
        case 28: return 8
        case 25: return 9
        // Numpad
        case 83: return 1
        case 84: return 2
        case 85: return 3
        case 86: return 4
        case 87: return 5
        case 88: return 6
        case 89: return 7
        case 91: return 8
        case 92: return 9
        default: return nil
        }
    }

    // MARK: - Snap Application

    private func applySnap(
        snapshot: FocusedWindowSnapshot,
        to region: RegionLayout.Region,
        on screen: NSScreen,
        layout: RegionLayout
    ) throws {
        let targetFrame = layoutEngine.frame(for: snapVisibleFrame(for: screen), region: region)
        var info = try windowController.moveWindow(snapshot, to: targetFrame)

        let widthDelta = abs(info.finalFrame.width - info.requestedFrame.width)
        let heightDelta = abs(info.finalFrame.height - info.requestedFrame.height)
        if widthDelta > 1 || heightDelta > 1 {
            // Some apps clamp the requested size. Re-anchor the window so oversized
            // results still align to the chosen edge instead of drifting inward.
            let correctedOrigin = correctedOrigin(
                for: region,
                requestedFrame: info.requestedFrame,
                actualSize: info.finalFrame.size
            )
            try windowController.setWindowPosition(snapshot, to: correctedOrigin)
            info = try windowController.moveWindow(snapshot, to: CGRect(origin: correctedOrigin, size: info.finalFrame.size))
            logger.warn(
                "Snap constrained by app min size: app=\(info.appName) bundle=\(info.bundleID) " +
                "requested=\(targetFrame.debugDescription) actual=\(info.finalFrame.debugDescription) " +
                "reappliedOrigin=\(correctedOrigin.debugDescription)"
            )
        }

        logger.info(
            "Snap success: app=\(info.appName) bundle=\(info.bundleID) pid=\(info.pid) " +
            "title=\"\(info.windowTitle)\" role=\(info.role)/\(info.subrole) " +
            "minimized=\(info.minimized) settable(pos=\(info.positionSettable),size=\(info.sizeSettable)) " +
            "layout=\(layout.id) region=\(region.id) requested=\(info.requestedFrame.debugDescription) final=\(info.finalFrame.debugDescription)"
        )
    }

    // MARK: - Picker State

    private func resetPicker() {
        snapPickerController.hide()
        previewOverlayController.hide()
        mouseDownLocation = nil
        currentScreen = nil
        pickerVisible = false
        hoveredSelection = nil
        initialWindowSnapshot = nil
        dragWindowConfirmed = false
    }

    // MARK: - Window Matching

    /// Returns the `NSScreen` whose frame contains the given global point.
    private func screen(at point: CGPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(point) })
    }

    private func isSameWindow(_ lhs: FocusedWindowSnapshot, _ rhs: FocusedWindowSnapshot) -> Bool {
        guard lhs.pid == rhs.pid, lhs.role == rhs.role, lhs.subrole == rhs.subrole else {
            return false
        }
        if lhs.windowTitle == rhs.windowTitle { return true }
        return abs(lhs.frame.width - rhs.frame.width) < 2 && abs(lhs.frame.height - rhs.frame.height) < 2
    }

    private func shouldConsiderWindow(_ snapshot: FocusedWindowSnapshot) -> Bool {
        guard snapshot.pid != selfPID else { return false }
        guard snapshot.subrole != "AXDialog", snapshot.role != "AXSheet" else { return false }
        guard snapshot.sizeSettable else { return false }
        return true
    }

    // MARK: - Geometry

    /// Re-anchors the window's origin when an app clamps the requested size.
    private func correctedOrigin(
        for region: RegionLayout.Region,
        requestedFrame: CGRect,
        actualSize: CGSize
    ) -> CGPoint {
        let epsilon = 0.0001
        let horizontalAnchor: CGFloat
        if region.normalizedFrame.minX <= epsilon {
            horizontalAnchor = requestedFrame.minX
        } else if region.normalizedFrame.maxX >= (1.0 - epsilon) {
            horizontalAnchor = requestedFrame.maxX - actualSize.width
        } else {
            horizontalAnchor = requestedFrame.midX - (actualSize.width / 2.0)
        }

        let verticalAnchor: CGFloat
        if region.normalizedFrame.minY <= epsilon {
            verticalAnchor = requestedFrame.minY
        } else if region.normalizedFrame.maxY >= (1.0 - epsilon) {
            verticalAnchor = requestedFrame.maxY - actualSize.height
        } else {
            verticalAnchor = requestedFrame.midY - (actualSize.height / 2.0)
        }

        return CGPoint(x: horizontalAnchor, y: verticalAnchor)
    }

    private func isModifierActive() -> Bool {
        !requiresModifierKey || NSEvent.modifierFlags.contains(requiredModifier.eventFlag)
    }

    private func snapVisibleFrame(for screen: NSScreen) -> CGRect {
        screen.visibleFrame.insetBy(dx: -3, dy: -3)
    }
}
