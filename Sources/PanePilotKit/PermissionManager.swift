import ApplicationServices
import Foundation

/// Thin wrapper around the macOS Accessibility trust API.
///
/// `PermissionManager` isolates all calls to `AXIsProcessTrustedWithOptions` behind a single
/// method so the rest of the codebase never needs to construct raw `CFDictionary` values or
/// reason about the `AXTrustedCheckOptionPrompt` key directly.
///
/// There are two usage patterns:
/// - **Silent check** (`prompt: false`): used during polling loops and drag events to test
///   whether permission is currently granted without disturbing the user.
/// - **Prompt** (`prompt: true`): used on first launch when permission is absent; macOS
///   shows the system alert and opens System Settings if the user agrees.
struct PermissionManager {
    /// Returns `true` when the current process has Accessibility permission.
    ///
    /// - Parameter prompt: When `true`, macOS presents the Accessibility permission alert if
    ///   the permission has not been granted yet. Pass `false` for silent polling.
    @discardableResult
    func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        // Callers use the non-prompting form during drag polling and reserve the prompting
        // form for explicit user actions in settings.
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
