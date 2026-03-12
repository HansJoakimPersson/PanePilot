import ApplicationServices
import Foundation

enum AppError: Error, LocalizedError {
    case invalidArguments(String)
    case accessibilityPermissionDenied
    case focusedApplicationUnavailable
    case focusedWindowUnavailable
    case axOperationFailed(String, AXError)

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
