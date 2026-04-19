import Foundation
import ServiceManagement

/// Errors thrown by `LoginItemManager`.
enum LoginItemManagerError: LocalizedError {
    /// The `SMAppService` call failed — e.g. the app is not a signed bundle.
    case operationFailed(String)
    /// The feature is structurally unavailable in this build (unsigned binary, swift run, etc.).
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .operationFailed(let message):
            return message
        case .unavailable(let message):
            return message
        }
    }
}

/// Manages the "Start at Login" launch-item registration for PanePilot.
///
/// On macOS 13+, registration uses `SMAppService.mainApp`, which requires the process to be a
/// properly signed `.app` bundle recognised by `launchd`. On earlier OS versions (and when the
/// feature is structurally unavailable), the class degrades gracefully: it tracks the
/// preference in `UserDefaults` so the UI stays consistent, but does not actually register a
/// login item.
///
/// Before calling `setEnabled(_:)`, check `isFeatureAvailable` and surface `unavailableReason`
/// in the UI if it returns `false`. Attempting to register an unsigned build will throw
/// `LoginItemManagerError.unavailable`.
@MainActor
final class LoginItemManager {
    static let shared = LoginItemManager()
    private let legacyPreferenceKey = "startAtLoginPreference"

    private init() {}

    // MARK: - Capability

    /// `true` when the running process is a signed `.app` bundle that `SMAppService` will accept.
    var isFeatureAvailable: Bool {
        AppSigning.isSignedBundleApp()
    }

    /// A human-readable explanation of why the feature is unavailable (for display in Settings).
    var unavailableReason: String {
        "Start at Login is unavailable because the app is currently unsigned. Sign and bundle PanePilot as a .app to enable this setting."
    }

    // MARK: - State

    /// Returns `true` if PanePilot is currently registered to launch at login.
    ///
    /// On macOS 13+ this queries `SMAppService.mainApp.status`; on earlier systems it reads
    /// the legacy `UserDefaults` key.
    func isEnabled() -> Bool {
        if #available(macOS 13, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return UserDefaults.standard.bool(forKey: legacyPreferenceKey)
    }

    // MARK: - Mutation

    /// Registers or unregisters PanePilot as a login item.
    ///
    /// - Throws: `LoginItemManagerError.unavailable` if the app is not a signed bundle.
    ///           `LoginItemManagerError.operationFailed` if `SMAppService` rejects the call.
    func setEnabled(_ enabled: Bool) throws {
        guard isFeatureAvailable else {
            throw LoginItemManagerError.unavailable(unavailableReason)
        }
        if #available(macOS 13, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                UserDefaults.standard.set(enabled, forKey: legacyPreferenceKey)
            } catch {
                let message = "Unable to update Start at Login (\(error.localizedDescription)). This may require a bundled/signed app build."
                throw LoginItemManagerError.operationFailed(message)
            }
            return
        }

        UserDefaults.standard.set(enabled, forKey: legacyPreferenceKey)
    }
}
