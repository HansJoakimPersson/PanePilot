import AppKit
@preconcurrency import CoreGraphics
import Foundation

/// Filters keyboard events before they reach the frontmost application.
///
/// The event tap is attached to the main run loop. Returning `nil` from its callback removes
/// events that PanePilot consumes; all other events are returned unchanged.
@MainActor
final class KeyboardEventInterceptor {
    typealias KeyDownHandler = @MainActor (_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags) -> Bool

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyDownHandler: KeyDownHandler?
    private var suppressedKeyCodes: Set<UInt16> = []

    @discardableResult
    func start(handler: @escaping KeyDownHandler) -> Bool {
        stop()
        keyDownHandler = handler

        let eventMask = eventMask(for: [.keyDown, .keyUp])
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: userInfo
        ) else {
            keyDownHandler = nil
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        runLoopSource = source
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }

        runLoopSource = nil
        eventTap = nil
        keyDownHandler = nil
        suppressedKeyCodes.removeAll()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp, suppressedKeyCodes.remove(keyCode) != nil {
            return nil
        }

        guard type == .keyDown, let keyDownHandler else {
            return Unmanaged.passUnretained(event)
        }

        let shouldSuppress = keyDownHandler(keyCode, modifierFlags(from: event.flags))
        guard shouldSuppress else {
            return Unmanaged.passUnretained(event)
        }

        suppressedKeyCodes.insert(keyCode)
        return nil
    }

    private func modifierFlags(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var modifiers: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        return modifiers
    }

    private func eventMask(for types: [CGEventType]) -> CGEventMask {
        types.reduce(0) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }
    }

    private nonisolated static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let interceptor = Unmanaged<KeyboardEventInterceptor>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
        return MainActor.assumeIsolated {
            interceptor.handle(type: type, event: event)
        }
    }
}
