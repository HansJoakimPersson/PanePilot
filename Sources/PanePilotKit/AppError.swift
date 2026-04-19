import ApplicationServices
import Foundation

/// Typed errors thrown by PanePilot's Accessibility and window-manipulation layer.
///
/// All cases map to conditions that can arise during normal operation (permission not granted,
/// target app has no window, AX API returns an error). Callers should handle them explicitly
/// rather than catching a generic `Error`, so that permission and AX failures surface clearly
/// in logs and are not silently swallowed.
enum AppError: Error, LocalizedError {
    /// A caller passed arguments that cannot produce a valid result (e.g. an unknown edge name).
    case invalidArguments(String)

    /// `AXIsProcessTrustedWithOptions` returned false. The snap operation cannot proceed.
    case accessibilityPermissionDenied

    /// The AX API could not identify a focused application. This can happen briefly during
    /// app switching or when the frontmost process has no AX presence.
    case focusedApplicationUnavailable

    /// The focused application has no AX-visible focused window. Common for apps that do not
    /// expose their window via the Accessibility API (e.g. some Electron apps).
    case focusedWindowUnavailable

    /// A specific AX API call failed. `operation` names the call site; `error` is the raw AXError.
    case axOperationFailed(String, AXError)

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return message
        case .accessibilityPermissionDenied:
            return "Accessibility permission is required. Grant it in System Settings > Privacy & Security > Accessibility."
        case .focusedApplicationUnavailable:
            return "No focused application found."
        case .focusedWindowUnavailable:
            return "No focused window found for the active application."
        case .axOperationFailed(let operation, let error):
            return "Accessibility operation failed (\(operation)): \(error.rawValue)"
        }
    }
}
