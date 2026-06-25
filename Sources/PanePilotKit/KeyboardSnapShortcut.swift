import AppKit
import Foundation

struct KeyboardSnapShortcut: Equatable {
    static let defaultShortcut = KeyboardSnapShortcut(
        modifiers: [.option],
        keyCode: 53
    )

    static let modifierMask: NSEvent.ModifierFlags = [.control, .option, .command, .shift]

    let modifiers: NSEvent.ModifierFlags
    let keyCode: UInt16

    init(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) {
        self.modifiers = modifiers.intersection(Self.modifierMask)
        self.keyCode = keyCode
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "+").map(String.init)
        guard parts.count == 2, let keyCode = UInt16(parts[1]) else { return nil }

        var flags: NSEvent.ModifierFlags = []
        for token in parts[0].split(separator: ",") {
            switch token {
            case "control": flags.insert(.control)
            case "option": flags.insert(.option)
            case "command": flags.insert(.command)
            case "shift": flags.insert(.shift)
            default: return nil
            }
        }

        guard !flags.isEmpty else { return nil }
        self.init(modifiers: flags, keyCode: keyCode)
    }

    var rawValue: String {
        let modifierTokens: [(NSEvent.ModifierFlags, String)] = [
            (.control, "control"),
            (.option, "option"),
            (.command, "command"),
            (.shift, "shift"),
        ]

        let encodedModifiers = modifierTokens
            .filter { modifiers.contains($0.0) }
            .map(\.1)
            .joined(separator: ",")

        return "\(encodedModifiers)+\(keyCode)"
    }

    var displayName: String {
        let names: [(NSEvent.ModifierFlags, String)] = [
            (.control, "Control"),
            (.option, "Option"),
            (.shift, "Shift"),
            (.command, "Command"),
        ]

        let modifierNames = names
            .filter { modifiers.contains($0.0) }
            .map(\.1)

        return (modifierNames + [Self.keyDisplayName(for: keyCode)]).joined(separator: " + ")
    }

    var warningMessage: String? {
        if keyCode == 53 {
            return "Escape is often handled by macOS or the active app before PanePilot sees it."
        }
        if modifiers == [.option] {
            return "Option alone conflicts with common macOS alternate actions."
        }
        if modifiers == [.shift] {
            return "Shift-only shortcuts are easy to trigger accidentally while typing."
        }
        return nil
    }

    func matches(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        keyCode == self.keyCode && modifierFlags.intersection(Self.modifierMask) == modifiers
    }

    static func keyDisplayName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Escape"
        case 123: return "Left Arrow"
        case 124: return "Right Arrow"
        case 125: return "Down Arrow"
        case 126: return "Up Arrow"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        case 29: return "0"
        default: return "Key \(keyCode)"
        }
    }
}
