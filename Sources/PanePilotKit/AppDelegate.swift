import AppKit
import Foundation

/// Top-level application controller bridged into the SwiftUI `App` via `@NSApplicationDelegateAdaptor`.
///
/// `AppDelegate` owns the app's three long-lived objects — `DisplayLayoutStore`,
/// `DragSnapController`, and `SettingsWindowPresenter` — and orchestrates their initialisation
/// in `applicationDidFinishLaunching`. It also:
///
/// - Sets the activation policy to `.accessory` so PanePilot lives only in the menu bar.
/// - Prompts for Accessibility permission on first launch, then polls until it is granted and
///   restarts the event monitors (global `NSEvent` monitors registered before Accessibility is
///   trusted do not receive events, requiring a full restart of the drag controller).
/// - Listens for `NSApplication.didChangeScreenParametersNotification` and refreshes the
///   display registry when the user connects, disconnects, or rearranges monitors.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dragSnapController: DragSnapController?
    private var displayLayoutStore: DisplayLayoutStore?
    /// Polls every second after the Accessibility prompt until the user grants permission.
    private var accessibilityPollTimer: Timer?

    public override init() {}

    // MARK: - Application Lifecycle

    public func applicationDidFinishLaunching(_ notification: Notification) {
        configureApplication()

        let store = makeDisplayLayoutStore()
        displayLayoutStore = store

        let dragController = makeDragSnapController(using: store)
        dragController.start()
        dragSnapController = dragController
        SettingsWindowPresenter.shared.configure(store: store, dragSnapController: dragController)

        DebugLogger.shared.setEnabled(AppPreferences.debugLoggingEnabled)
        observeScreenChanges()
    }

    /// Initial app-level configuration: activation policy, icon, and accessibility check.
    private func configureApplication() {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = AppIconProvider.applicationIconImage()
        DebugLogger.shared.info("PanePilot app launched.")
        promptForAccessibilityIfNeeded()
    }

    /// Shows the macOS Accessibility permission alert if the app is not yet trusted.
    ///
    /// The prompt is deferred by 0.5 s so the menu bar is fully visible before the system
    /// alert appears. After prompting, `startPollingForAccessibility()` is called to watch for
    /// the grant and restart the event monitors once it arrives.
    private func promptForAccessibilityIfNeeded() {
        guard !PermissionManager().ensureAccessibilityPermission(prompt: false) else { return }
        DebugLogger.shared.info("Accessibility permission missing — prompting user.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            PermissionManager().ensureAccessibilityPermission(prompt: true)
            self?.startPollingForAccessibility()
        }
    }

    /// Starts a 1 Hz timer that restarts the drag controller once Accessibility is granted.
    ///
    /// The timer invalidates itself as soon as `AXIsProcessTrustedWithOptions` returns `true`,
    /// then calls `DragSnapController.restart()` to re-register the global event monitors with
    /// an already-trusted process. Without this restart, events received before the permission
    /// grant are silently dropped by the system.
    private func startPollingForAccessibility() {
        // Ignore the `timer` parameter to avoid a Sendable violation — `Timer` is not
        // `Sendable`, so it cannot cross the actor boundary into `assumeIsolated`.
        // Instead we invalidate via `self.accessibilityPollTimer`, which is safe because
        // both the reference and the mutation happen on the main actor.
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // The timer fires on the main run loop, so it is safe to assert main-actor
            // isolation here without scheduling an async hop.
            MainActor.assumeIsolated {
                guard let self else { return }
                guard PermissionManager().ensureAccessibilityPermission(prompt: false) else { return }
                self.accessibilityPollTimer?.invalidate()
                self.accessibilityPollTimer = nil
                DebugLogger.shared.info("Accessibility granted — restarting event monitors.")
                self.dragSnapController?.restart()
            }
        }
    }

    private func makeDisplayLayoutStore() -> DisplayLayoutStore {
        let store = DisplayLayoutStore(layouts: RegionLayouts.all)
        store.refreshConnectedDisplays()
        return store
    }

    private func makeDragSnapController(using store: DisplayLayoutStore) -> DragSnapController {
        let dragController = DragSnapController(
            permissions: PermissionManager(),
            screens: ScreenProvider(),
            layoutEngine: LayoutEngine(),
            windowController: WindowController(),
            displayLayoutStore: store
        )
        dragController.setRequiredModifier(AppPreferences.snapModifier)
        dragController.setKeyboardSnapShortcut(AppPreferences.keyboardSnapShortcut)
        return dragController
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.handleScreenParametersChanged()
            }
        }
    }

    // MARK: - Notifications

    private func handleScreenParametersChanged() {
        displayLayoutStore?.refreshConnectedDisplays()
        DebugLogger.shared.info("Screen parameters changed. Display registry refreshed.")
    }
}
