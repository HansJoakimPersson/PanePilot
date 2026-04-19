import AppKit
import Foundation

/// The keyboard modifier key the user must hold while dragging to activate snap.
///
/// The active modifier is stored as a `String` rawValue in `UserDefaults` via `AppPreferences`
/// so the setting survives app updates. `CaseIterable` conformance lets the Settings UI build
/// a picker without hardcoding the list of cases.
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
