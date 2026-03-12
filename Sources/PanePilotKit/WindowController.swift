import ApplicationServices
import CoreGraphics
import AppKit
import Foundation

struct WindowDebugInfo {
    let pid: pid_t
    let appName: String
    let bundleID: String
    let windowTitle: String
    let role: String
    let subrole: String
    let positionSettable: Bool
    let sizeSettable: Bool
    let minimized: Bool
    let requestedFrame: CGRect
    let finalFrame: CGRect
}

struct FocusedWindowSnapshot {
    let element: AXUIElement
    let pid: pid_t
    let appName: String
    let bundleID: String
    let windowTitle: String
    let role: String
    let subrole: String
    let frame: CGRect
    let positionSettable: Bool
    let sizeSettable: Bool
    let minimized: Bool
}

struct WindowController {
    func snapshotWindowForDrag(at point: CGPoint) -> FocusedWindowSnapshot? {
        // Prefer focused window for stability, but fall back to hit-testing under cursor.
        snapshotFocusedWindow() ?? snapshotWindowUnderCursor(at: point)
    }

    func snapshotFocusedWindow() -> FocusedWindowSnapshot? {
        guard let (appElement, windowElement) = focusedAppAndWindow() else {
            return nil
        }

        var pid: pid_t = 0
        AXUIElementGetPid(appElement, &pid)
        let running = NSRunningApplication(processIdentifier: pid)

        let position = pointAttribute(kAXPositionAttribute as String, from: windowElement)
        let size = sizeAttribute(kAXSizeAttribute as String, from: windowElement)
        let frame = appKitFrame(axOrigin: position, size: size)

        return FocusedWindowSnapshot(
            element: windowElement,
            pid: pid,
            appName: running?.localizedName ?? "unknown",
            bundleID: running?.bundleIdentifier ?? "unknown",
            windowTitle: stringAttribute(kAXTitleAttribute as String, from: windowElement),
            role: stringAttribute(kAXRoleAttribute as String, from: windowElement),
            subrole: stringAttribute(kAXSubroleAttribute as String, from: windowElement),
            frame: frame,
            positionSettable: isSettable(attribute: kAXPositionAttribute as String, on: windowElement),
            sizeSettable: isSettable(attribute: kAXSizeAttribute as String, on: windowElement),
            minimized: boolAttribute(kAXMinimizedAttribute as String, from: windowElement)
        )
    }

    func snapshotWindowUnderCursor(at point: CGPoint) -> FocusedWindowSnapshot? {
        let systemWide = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &elementRef)
        guard status == .success, let element = elementRef else {
            return nil
        }
        guard let windowElement = ancestorWindow(from: element) else {
            return nil
        }

        var pid: pid_t = 0
        AXUIElementGetPid(windowElement, &pid)
        let running = NSRunningApplication(processIdentifier: pid)

        let position = pointAttribute(kAXPositionAttribute as String, from: windowElement)
        let size = sizeAttribute(kAXSizeAttribute as String, from: windowElement)
        let frame = appKitFrame(axOrigin: position, size: size)

        return FocusedWindowSnapshot(
            element: windowElement,
            pid: pid,
            appName: running?.localizedName ?? "unknown",
            bundleID: running?.bundleIdentifier ?? "unknown",
            windowTitle: stringAttribute(kAXTitleAttribute as String, from: windowElement),
            role: stringAttribute(kAXRoleAttribute as String, from: windowElement),
            subrole: stringAttribute(kAXSubroleAttribute as String, from: windowElement),
            frame: frame,
            positionSettable: isSettable(attribute: kAXPositionAttribute as String, on: windowElement),
            sizeSettable: isSettable(attribute: kAXSizeAttribute as String, on: windowElement),
            minimized: boolAttribute(kAXMinimizedAttribute as String, from: windowElement)
        )
    }

    func moveWindow(_ snapshot: FocusedWindowSnapshot, to frame: CGRect) throws -> WindowDebugInfo {
        try setPosition(windowElement: snapshot.element, frame: frame)
        try setSize(windowElement: snapshot.element, frame: frame)
        let finalFrame = frameOfWindowElement(snapshot.element)

        return WindowDebugInfo(
            pid: snapshot.pid,
            appName: snapshot.appName,
            bundleID: snapshot.bundleID,
            windowTitle: snapshot.windowTitle,
            role: snapshot.role,
            subrole: snapshot.subrole,
            positionSettable: snapshot.positionSettable,
            sizeSettable: snapshot.sizeSettable,
            minimized: snapshot.minimized,
            requestedFrame: frame,
            finalFrame: finalFrame
        )
    }

    func moveFocusedWindow(to frame: CGRect) throws -> WindowDebugInfo {
        guard let (appElement, windowElement) = focusedAppAndWindow() else {
            throw AppError.focusedApplicationUnavailable
        }

        let debugInfo = inspect(appElement: appElement, windowElement: windowElement)
        try setPosition(windowElement: windowElement, frame: frame)
        try setSize(windowElement: windowElement, frame: frame)
        let finalFrame = frameOfWindowElement(windowElement)
        return WindowDebugInfo(
            pid: debugInfo.pid,
            appName: debugInfo.appName,
            bundleID: debugInfo.bundleID,
            windowTitle: debugInfo.windowTitle,
            role: debugInfo.role,
            subrole: debugInfo.subrole,
            positionSettable: debugInfo.positionSettable,
            sizeSettable: debugInfo.sizeSettable,
            minimized: debugInfo.minimized,
            requestedFrame: frame,
            finalFrame: finalFrame
        )
    }

    func setWindowPosition(_ snapshot: FocusedWindowSnapshot, to origin: CGPoint) throws {
        var updated = snapshot.frame
        updated.origin = origin
        try setPosition(windowElement: snapshot.element, frame: updated)
    }

    private func ancestorWindow(from element: AXUIElement, maxDepth: Int = 8) -> AXUIElement? {
        var current: AXUIElement? = element
        var depth = 0
        while let node = current, depth < maxDepth {
            let role = stringAttribute(kAXRoleAttribute as String, from: node)
            if role == kAXWindowRole as String {
                return node
            }
            var parentRef: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(node, kAXParentAttribute as CFString, &parentRef)
            guard status == .success, let parent = parentRef else {
                return nil
            }
            current = unsafeDowncast(parent as AnyObject, to: AXUIElement.self)
            depth += 1
        }
        return nil
    }

    private func focusedAppAndWindow() -> (AXUIElement, AXUIElement)? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedAppRef: CFTypeRef?
        let appStatus = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppRef)
        guard appStatus == .success, let focusedApp = focusedAppRef else {
            return nil
        }

        let appElement = unsafeDowncast(focusedApp as AnyObject, to: AXUIElement.self)
        var focusedWindowRef: CFTypeRef?
        let windowStatus = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)
        guard windowStatus == .success, let focusedWindow = focusedWindowRef else {
            return nil
        }

        let windowElement = unsafeDowncast(focusedWindow as AnyObject, to: AXUIElement.self)
        return (appElement, windowElement)
    }

    private func setPosition(windowElement: AXUIElement, frame: CGRect) throws {
        var origin = axOrigin(forAppKitFrame: frame)
        guard let positionValue = AXValueCreate(.cgPoint, &origin) else {
            throw AppError.invalidArguments("Could not create AX point.")
        }
        let status = AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, positionValue)
        guard status == .success else {
            throw AppError.axOperationFailed("set position", status)
        }
    }

    private func setSize(windowElement: AXUIElement, frame: CGRect) throws {
        var size = CGSize(width: frame.size.width, height: frame.size.height)
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw AppError.invalidArguments("Could not create AX size.")
        }
        let status = AXUIElementSetAttributeValue(windowElement, kAXSizeAttribute as CFString, sizeValue)
        guard status == .success else {
            throw AppError.axOperationFailed("set size", status)
        }
    }

    private func inspect(appElement: AXUIElement, windowElement: AXUIElement) -> WindowDebugInfo {
        var pid: pid_t = 0
        AXUIElementGetPid(appElement, &pid)
        let running = NSRunningApplication(processIdentifier: pid)

        return WindowDebugInfo(
            pid: pid,
            appName: running?.localizedName ?? "unknown",
            bundleID: running?.bundleIdentifier ?? "unknown",
            windowTitle: stringAttribute(kAXTitleAttribute as String, from: windowElement),
            role: stringAttribute(kAXRoleAttribute as String, from: windowElement),
            subrole: stringAttribute(kAXSubroleAttribute as String, from: windowElement),
            positionSettable: isSettable(attribute: kAXPositionAttribute as String, on: windowElement),
            sizeSettable: isSettable(attribute: kAXSizeAttribute as String, on: windowElement),
            minimized: boolAttribute(kAXMinimizedAttribute as String, from: windowElement),
            requestedFrame: .zero,
            finalFrame: .zero
        )
    }

    private func isSettable(attribute: String, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let status = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return status == .success ? settable.boolValue : false
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String {
        var valueRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef)
        guard status == .success, let value = valueRef as? String else {
            return "n/a"
        }
        return value
    }

    private func boolAttribute(_ attribute: String, from element: AXUIElement) -> Bool {
        var valueRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef)
        guard status == .success, let value = valueRef as? Bool else {
            return false
        }
        return value
    }

    private func pointAttribute(_ attribute: String, from element: AXUIElement) -> CGPoint {
        var valueRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef)
        guard status == .success, let rawValue = valueRef else {
            return .zero
        }
        guard CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return .zero
        }
        let axValue = rawValue as! AXValue
        var point = CGPoint.zero
        if AXValueGetValue(axValue, .cgPoint, &point) {
            return point
        }
        return .zero
    }

    private func sizeAttribute(_ attribute: String, from element: AXUIElement) -> CGSize {
        var valueRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef)
        guard status == .success, let rawValue = valueRef else {
            return .zero
        }
        guard CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return .zero
        }
        let axValue = rawValue as! AXValue
        var size = CGSize.zero
        if AXValueGetValue(axValue, .cgSize, &size) {
            return size
        }
        return .zero
    }

    private func frameOfWindowElement(_ element: AXUIElement) -> CGRect {
        let position = pointAttribute(kAXPositionAttribute as String, from: element)
        let size = sizeAttribute(kAXSizeAttribute as String, from: element)
        return appKitFrame(axOrigin: position, size: size)
    }

    private func appKitFrame(axOrigin: CGPoint, size: CGSize) -> CGRect {
        let desktop = desktopFrame()
        return CGRect(
            x: axOrigin.x,
            y: desktop.maxY - axOrigin.y - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func axOrigin(forAppKitFrame frame: CGRect) -> CGPoint {
        let desktop = desktopFrame()
        return CGPoint(
            x: frame.origin.x,
            y: desktop.maxY - frame.maxY
        )
    }

    private func desktopFrame() -> CGRect {
        NSScreen.screens.map(\.frame).reduce(.null) { partial, frame in
            partial.union(frame)
        }
    }
}
