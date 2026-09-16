import AppKit
@preconcurrency import CoreGraphics
import ApplicationServices
import Foundation

/// Filters keyboard events before they reach the frontmost application.
///
/// The event tap is attached to the main run loop. Returning `nil` from its callback removes
/// events that PanePilot consumes; all other events are returned unchanged.
@MainActor
final class KeyboardEventInterceptor {
    typealias KeyDownHandler = @MainActor (_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags) -> Bool

    enum StartResult {
        case started
        case accessibilityUnavailable
        case creationFailed
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyDownHandler: KeyDownHandler?
    private var suppressedKeyCodes: Set<UInt16> = []

    @discardableResult
    func start(handler: @escaping KeyDownHandler) -> StartResult {
        stop()
        keyDownHandler = handler

        let options = ["AXTrustedCheckOptionPrompt": false] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            DebugLogger.shared.info("KeyboardEventInterceptor: event tap deferred until Accessibility permission is granted.")
            keyDownHandler = nil
            return .accessibilityUnavailable
        }

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
            DebugLogger.shared.error("KeyboardEventInterceptor: unable to create event tap after Accessibility permission was granted.")
            keyDownHandler = nil
            return .creationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        runLoopSource = source
        DebugLogger.shared.info("KeyboardEventInterceptor: event tap started.")
        return .started
    }

    func stop() {
        guard eventTap != nil || runLoopSource != nil else { return }
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
        DebugLogger.shared.info("KeyboardEventInterceptor: event tap stopped.")
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout {
            DebugLogger.shared.warn("KeyboardEventInterceptor: tap disabled by timeout — re-enabling.")
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByUserInput {
            // Accessibility was revoked. AppDelegate's distributed notification observer
            // handles the primary stop; this is a safety net in case the notification
            // fires after an event is already in flight.
            DebugLogger.shared.error("KeyboardEventInterceptor: tap disabled by user (accessibility revoked) — stopping.")
            Task { @MainActor [weak self] in self?.stop() }
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
