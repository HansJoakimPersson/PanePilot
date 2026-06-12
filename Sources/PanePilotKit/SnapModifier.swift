import AppKit
import Foundation

enum SnapModifier: String, CaseIterable {
    case control
    case option
    case command
    case shift

    // MARK: - Presentation

    /// Human-readable name shown in Settings (e.g. "Command", "Option").
    var displayName: String {
        switch self {
        case .control: return "Control"
        case .option: return "Option"
        case .command: return "Command"
        case .shift: return "Shift"
        }
    }

    // MARK: - NSEvent Bridge

    /// The corresponding `NSEvent.ModifierFlags` bit, used when testing global drag events.
    var eventFlag: NSEvent.ModifierFlags {
        switch self {
        case .control: return .control
        case .option: return .option
        case .command: return .command
        case .shift: return .shift
        }
    }
}

/// Modifier combination the user must hold while dragging to activate snap regions.
struct DragSnapModifier: Equatable {
    static let defaultModifier = DragSnapModifier(modifiers: [.command])

    let modifiers: NSEvent.ModifierFlags

    init(modifiers: NSEvent.ModifierFlags) {
        self.modifiers = modifiers.intersection(KeyboardSnapShortcut.modifierMask)
    }

    init?(rawValue: String) {
        if let legacyModifier = SnapModifier(rawValue: rawValue) {
            self.init(modifiers: legacyModifier.eventFlag)
            return
        }

        var flags: NSEvent.ModifierFlags = []
        for token in rawValue.split(separator: ",") {
            switch token {
            case "control": flags.insert(.control)
            case "option": flags.insert(.option)
            case "command": flags.insert(.command)
            case "shift": flags.insert(.shift)
            default: return nil
            }
        }

        guard !flags.isEmpty else { return nil }
        self.init(modifiers: flags)
    }

    var rawValue: String {
        let modifierTokens: [(NSEvent.ModifierFlags, String)] = [
            (.control, "control"),
            (.option, "option"),
            (.command, "command"),
            (.shift, "shift"),
        ]

        return modifierTokens
            .filter { modifiers.contains($0.0) }
            .map(\.1)
            .joined(separator: ",")
    }

    var displayName: String {
        let names: [(NSEvent.ModifierFlags, String)] = [
            (.control, "Control"),
            (.option, "Option"),
            (.shift, "Shift"),
            (.command, "Command"),
        ]

        return names
            .filter { modifiers.contains($0.0) }
            .map(\.1)
            .joined(separator: " + ")
    }

    var warningMessage: String? {
        if modifiers == [.option] {
            return "Option alone conflicts with common macOS alternate actions."
        }
        if modifiers == [.shift] {
            return "Shift alone is easy to trigger accidentally while typing."
        }
        return nil
    }

    func matches(modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let activeModifiers = modifierFlags.intersection(KeyboardSnapShortcut.modifierMask)
        return activeModifiers.isSuperset(of: modifiers)
    }
}
