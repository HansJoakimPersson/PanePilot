import Foundation
import Security

enum AppSigning {
    // Start-at-login only works for a real bundled app, so detect that early and surface
    // a clear explanation in settings instead of letting ServiceManagement fail opaquely.
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
