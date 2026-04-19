import Foundation
import Security

/// Utilities for inspecting the running app's code-signing state.
///
/// Certain features — most notably start-at-login via `SMAppService` — only work when the
/// app is running from a properly signed `.app` bundle. `AppSigning` provides a cheap
/// runtime check so callers can surface a meaningful explanation in the UI rather than letting
/// lower-level APIs fail silently or with opaque error codes.
enum AppSigning {
    /// Returns `true` when the running process is a signed `.app` bundle.
    ///
    /// The check has two layers:
    /// 1. The bundle URL must have an `.app` extension — this rejects plain SwiftPM executables
    ///    and `swift run` invocations.
    /// 2. `SecStaticCodeCheckValidity` must succeed — this rejects unsigned or ad-hoc–signed
    ///    bundles that macOS would refuse for privileged operations.
    ///
    /// Note: ad-hoc signing (`codesign --sign -`) passes step 1 but fails step 2, so `make run`
    /// builds return `false` here. Only a properly signed developer or distribution build returns
    /// `true`.
    static func isSignedBundleApp() -> Bool {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension.lowercased() == "app" else {
            return false
        }

        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return false
        }

        let checkStatus = SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil)
        return checkStatus == errSecSuccess
    }
}
