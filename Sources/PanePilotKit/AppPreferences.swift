import Foundation

enum AppPreferences {
    private static let snapModifierKey = "snapModifier"
    private static let debugLoggingEnabledKey = "debugLoggingEnabled"

    static var snapModifier: SnapModifier {
        get {
            let raw = UserDefaults.standard.string(forKey: snapModifierKey) ?? SnapModifier.command.rawValue
            return SnapModifier(rawValue: raw) ?? .command
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: snapModifierKey)
        }
    }

    static var debugLoggingEnabled: Bool {
        get {
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
