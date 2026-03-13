import ApplicationServices
import Foundation

struct PermissionManager {
    func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        // Callers use the non-prompting form during drag polling and reserve the prompting
        // form for explicit user actions in settings.
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
