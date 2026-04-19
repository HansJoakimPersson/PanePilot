import AppKit
import Foundation

/// A snapshot of a single physical display at a point in time.
///
/// `ScreenInfo` captures the CoreGraphics display ID, the full screen frame (in AppKit
/// coordinates), and whether the display is the primary (menu-bar) display. It is used
/// throughout the snap pipeline where passing raw `NSScreen` objects would be fragile due to
/// AppKit's lazy screen-list invalidation.
struct ScreenInfo {
    /// CoreGraphics display identifier — stable for the lifetime of the display connection.
    let id: CGDirectDisplayID
    /// Full screen frame in global AppKit (flipped) coordinates, including the menu bar area.
    let frame: CGRect
    /// `true` when this is the primary display (the one that shows the menu bar).
    let isPrimary: Bool

    /// Human-readable one-liner for use in log messages.
    var description: String {
        let primaryMarker = isPrimary ? "primary" : "secondary"
        return "display=\(id) role=\(primaryMarker) frame=\(frame.debugDescription)"
    }
}

/// Queries the current display configuration from AppKit and CoreGraphics.
///
/// `ScreenProvider` bridges the `NSScreen` API (which uses AppKit display descriptions) and
/// the CoreGraphics `CGDirectDisplayID` (which is needed for layout-to-screen association).
/// All methods read live state from the system — call them at event time rather than caching
/// results, since display configurations change when the user connects or disconnects monitors.
struct ScreenProvider {
    // MARK: - Display Identification

    /// Returns the CoreGraphics display ID for the given `NSScreen`, or `nil` if unavailable.
    ///
    /// AppKit exposes the CG display number through the screen's device description dictionary
    /// under the key `"NSScreenNumber"`. This is the standard bridge between the two APIs.
    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        // AppKit exposes the CoreGraphics display number through the screen device dictionary.
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    // MARK: - Queries

    /// Returns `ScreenInfo` for every currently connected display.
    ///
    /// Screens without a resolvable CG display ID are silently omitted — this is unusual but
    /// can occur with virtual displays or during display reconfiguration.
    func fetchScreens() -> [ScreenInfo] {
        let primaryID = CGMainDisplayID()
        return NSScreen.screens.compactMap { screen in
            guard let id = ScreenProvider.displayID(for: screen) else {
                return nil
            }
            return ScreenInfo(id: id, frame: screen.frame, isPrimary: id == primaryID)
        }
    }

    /// Returns the primary (menu-bar) display, falling back to a synthetic 1920×1080 entry.
    ///
    /// The fallback is a last-resort guard; in practice `CGMainDisplayID()` always resolves.
    func primaryScreen() -> ScreenInfo {
        fetchScreens().first(where: { $0.isPrimary })
            ?? ScreenInfo(id: CGMainDisplayID(), frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isPrimary: true)
    }
}
