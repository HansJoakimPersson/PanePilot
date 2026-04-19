import AppKit
import Foundation

/// Presents the Settings window on demand from any call site.
///
/// `SettingsWindowPresenter` is the single point through which the rest of the app opens
/// Settings. It manages the `SettingsWindowController` lifecycle, handles the AppKit
/// activation-policy dance required to make a menu-bar app's window behave like a regular app
/// window, and tears down the controller when the window closes.
///
/// Call `configure(store:dragSnapController:)` once during app launch before any `show()` call.
/// `show()` is safe to call from any context — it dispatches to the main queue internally.
@MainActor
public final class SettingsWindowPresenter {
    public static let shared = SettingsWindowPresenter()

    private var controller: SettingsWindowController?
    private weak var dragSnapController: DragSnapController?
    private var store: DisplayLayoutStore?

    private init() {}

    // MARK: - Configuration

    /// Provides the dependencies needed to create `SettingsWindowController`.
    ///
    /// Must be called before `show()`. Safe to call multiple times — subsequent calls replace
    /// the stored references (the previous controller, if any, is released).
    func configure(store: DisplayLayoutStore, dragSnapController: DragSnapController) {
        self.store = store
        self.dragSnapController = dragSnapController
    }

    // MARK: - Presentation

    /// Opens the Settings window, creating the controller if needed.
    ///
    /// Dispatches to the main queue, so it is safe to call from any thread or async context.
    public func show() {
        DebugLogger.shared.info("SettingsWindowPresenter.show: entered.")
        DispatchQueue.main.async { [weak self] in
            self?.showOnMain()
        }
    }

    private func showOnMain() {
        guard let store else {
            DebugLogger.shared.error("SettingsWindowPresenter.showOnMain: display store is not configured.")
            return
        }

        if controller == nil {
            DebugLogger.shared.info("SettingsWindowPresenter.showOnMain: creating controller.")
            controller = makeController(store: store)
        }

        guard let controller else {
            DebugLogger.shared.error("SettingsWindowPresenter.showOnMain: failed to create settings controller.")
            return
        }

        prepareApplicationForSettingsWindow()
        DebugLogger.shared.info("SettingsWindowPresenter.showOnMain: presenting settings window.")
        controller.present()
        if let window = controller.window {
            window.level = .normal
            DebugLogger.shared.info(
                "SettingsWindowPresenter.showOnMain: post-present visible=\(window.isVisible) key=\(window.isKeyWindow) frame=\(window.frame.debugDescription)"
            )
        }
    }

    /// Temporarily promotes the app from `.accessory` to `.regular` activation policy.
    ///
    /// PanePilot normally runs as an accessory (menu-bar only, no Dock icon). Showing a
    /// standard window requires `.regular` policy so macOS creates a proper window level and
    /// the window can become key. `restoreAccessoryMode()` reverses this when the window
    /// closes. The Dock icon and app switcher entry appear only while the window is onscreen.
    private func prepareApplicationForSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppIconProvider.applicationIconImage()
        NSApp.dockTile.display()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func restoreAccessoryMode() {
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Controller Lifecycle

    private func makeController(store: DisplayLayoutStore) -> SettingsWindowController {
        let controller = SettingsWindowController(
            store: store,
            initialSnapModifier: AppPreferences.snapModifier,
            onSnapModifierChanged: { [weak self] modifier in
                AppPreferences.snapModifier = modifier
                self?.dragSnapController?.setRequiredModifier(modifier)
            },
            onDebugLoggingChanged: { enabled in
                DebugLogger.shared.setEnabled(enabled)
            }
        )

        controller.onWindowClosed = { [weak self] in
            DebugLogger.shared.info("SettingsWindowPresenter: window closed.")
            self?.controller = nil
            self?.restoreAccessoryMode()
        }

        return controller
    }
}
