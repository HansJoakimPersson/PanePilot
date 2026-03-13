import AppKit
import Foundation

struct ScreenInfo {
    let id: CGDirectDisplayID
    let frame: CGRect
    let isPrimary: Bool

    var description: String {
        let primaryMarker = isPrimary ? "primary" : "secondary"
        return "display=\(id) role=\(primaryMarker) frame=\(frame.debugDescription)"
    }
}

struct ScreenProvider {
    // MARK: - Display Identification

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        // AppKit exposes the CoreGraphics display number through the screen device dictionary.
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    // MARK: - Queries

    func fetchScreens() -> [ScreenInfo] {
        let primaryID = CGMainDisplayID()
        return NSScreen.screens.compactMap { screen in
            guard let id = ScreenProvider.displayID(for: screen) else {
                return nil
            }
            return ScreenInfo(id: id, frame: screen.frame, isPrimary: id == primaryID)
        }
    }

    func primaryScreen() -> ScreenInfo {
        fetchScreens().first(where: { $0.isPrimary })
            ?? ScreenInfo(id: CGMainDisplayID(), frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isPrimary: true)
    }
}
