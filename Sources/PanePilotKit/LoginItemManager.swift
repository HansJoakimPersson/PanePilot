import Foundation
import ServiceManagement

enum LoginItemManagerError: LocalizedError {
    case operationFailed(String)
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

@MainActor
final class LoginItemManager {
    static let shared = LoginItemManager()
    private let legacyPreferenceKey = "startAtLoginPreference"

    private init() {}

    // MARK: - Capability

    var isFeatureAvailable: Bool {
        AppSigning.isSignedBundleApp()
    }

    var unavailableReason: String {
        "Start at Login is unavailable because the app is currently unsigned. Sign and bundle PanePilot as a .app to enable this setting."
    }

    // MARK: - State

    func isEnabled() -> Bool {
        if #available(macOS 13, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return UserDefaults.standard.bool(forKey: legacyPreferenceKey)
    }

    // MARK: - Mutation

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
