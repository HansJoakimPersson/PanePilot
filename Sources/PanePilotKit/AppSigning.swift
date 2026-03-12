import Foundation
import Security

enum AppSigning {
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
