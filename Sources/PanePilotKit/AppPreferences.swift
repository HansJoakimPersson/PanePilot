import Foundation

/// Typed accessors for all user-facing `UserDefaults` preferences.
///
/// `AppPreferences` is a namespace enum (no instances) that wraps raw `UserDefaults` keys in
/// strongly-typed Swift properties. Each property defines its own default so callers never
/// need to guard against missing keys. Mutating a property writes through to
/// `UserDefaults.standard` immediately — there is no separate "save" step.
enum AppPreferences {
    private static let snapModifierKey = "snapModifier"
    private static let snapModifierEnabledKey = "snapModifierEnabled"
    private static let keyboardSnapShortcutKey = "keyboardSnapShortcut"
    private static let keyboardSnapShortcutEnabledKey = "keyboardSnapShortcutEnabled"
    private static let debugLoggingEnabledKey = "debugLoggingEnabled"

    // MARK: - Drag Snap

    /// The keyboard modifier combination the user must hold while dragging to activate snap.
    ///
    /// Defaults to Command on first launch. Legacy single-modifier raw values are still
    /// accepted so older user preferences migrate without a separate migration step. A `nil`
    /// value means Drag Snap is disabled until the user records a modifier again.
    static var snapModifier: DragSnapModifier? {
        get {
            if UserDefaults.standard.object(forKey: snapModifierEnabledKey) != nil,
               !UserDefaults.standard.bool(forKey: snapModifierEnabledKey) {
                return nil
            }
            guard let raw = UserDefaults.standard.string(forKey: snapModifierKey),
                  let modifier = DragSnapModifier(rawValue: raw) else {
                return .defaultModifier
            }
            return modifier
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: snapModifierKey)
                UserDefaults.standard.set(true, forKey: snapModifierEnabledKey)
            } else {
                UserDefaults.standard.set(false, forKey: snapModifierEnabledKey)
            }
        }
    }

    /// The complete hotkey that opens keyboard snap mode without dragging.
    ///
    /// Defaults to Option + Escape. Stored independently from the drag snap modifier
    /// so users can avoid conflicts in either workflow without coupling the two settings.
    static var keyboardSnapShortcut: KeyboardSnapShortcut? {
        get {
            if UserDefaults.standard.object(forKey: keyboardSnapShortcutEnabledKey) != nil,
               !UserDefaults.standard.bool(forKey: keyboardSnapShortcutEnabledKey) {
                return nil
            }
            guard let raw = UserDefaults.standard.string(forKey: keyboardSnapShortcutKey),
                  let shortcut = KeyboardSnapShortcut(rawValue: raw) else {
                return .defaultShortcut
            }
            return shortcut
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: keyboardSnapShortcutKey)
                UserDefaults.standard.set(true, forKey: keyboardSnapShortcutEnabledKey)
            } else {
                UserDefaults.standard.set(false, forKey: keyboardSnapShortcutEnabledKey)
            }
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
