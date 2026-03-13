import AppKit
import Foundation

enum SnapModifier: String, CaseIterable {
    case control
    case option
    case command
    case shift

    // MARK: - Presentation

    var displayName: String {
        switch self {
        case .control: return "Control"
        case .option: return "Option"
        case .command: return "Command"
        case .shift: return "Shift"
        }
    }

    // MARK: - NSEvent Bridge

    var eventFlag: NSEvent.ModifierFlags {
        switch self {
        case .control: return .control
        case .option: return .option
        case .command: return .command
        case .shift: return .shift
        }
    }
}
