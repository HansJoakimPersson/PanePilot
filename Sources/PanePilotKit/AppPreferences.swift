import Foundation

/// Typed accessors for all user-facing `UserDefaults` preferences.
///
/// `AppPreferences` is a namespace enum (no instances) that wraps raw `UserDefaults` keys in
/// strongly-typed Swift properties. Each property defines its own default so callers never
/// need to guard against missing keys. Mutating a property writes through to
/// `UserDefaults.standard` immediately — there is no separate "save" step.
enum AppPreferences {
    private static let snapModifierKey = "snapModifier"
    private static let debugLoggingEnabledKey = "debugLoggingEnabled"

    // MARK: - Drag Snap

    /// The keyboard modifier the user must hold while dragging to activate snap.
    ///
    /// Defaults to `.command` on first launch. The raw string value is persisted so the
    /// preference survives app updates that reorder or rename enum cases.
    static var snapModifier: SnapModifier {
        get {
            let raw = UserDefaults.standard.string(forKey: snapModifierKey) ?? SnapModifier.command.rawValue
            return SnapModifier(rawValue: raw) ?? .command
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: snapModifierKey)
        }
    }

    // MARK: - Diagnostics

    /// Whether verbose debug logging is written to `DebugLogger`.
    ///
    /// Defaults to `true` for new installs so that setup and permission problems leave a trace
    /// in the log without the user having to opt in first. Users can disable logging in
    /// Settings once everything is working.
    static var debugLoggingEnabled: Bool {
        get {
            // Treat a missing key as `true` (default-on for new installs).
            if UserDefaults.standard.object(forKey: debugLoggingEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: debugLoggingEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: debugLoggingEnabledKey)
        }
    }
}
