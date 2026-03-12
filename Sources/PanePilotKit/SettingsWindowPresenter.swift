import AppKit
import Foundation

@MainActor
public final class SettingsWindowPresenter {
    public static let shared = SettingsWindowPresenter()

    private var controller: SettingsWindowController?
    private weak var dragSnapController: DragSnapController?
    private var store: DisplayLayoutStore?

    private init() {}

    func configure(store: DisplayLayoutStore, dragSnapController: DragSnapController) {
        self.store = store
        self.dragSnapController = dragSnapController
    }

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

        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppIconProvider.applicationIconImage()
        NSApp.dockTile.display()
        NSApp.activate(ignoringOtherApps: true)
        DebugLogger.shared.info("SettingsWindowPresenter.showOnMain: presenting settings window.")
        controller.present()
        if let window = controller.window {
            window.level = .normal
            DebugLogger.shared.info(
                "SettingsWindowPresenter.showOnMain: post-present visible=\(window.isVisible) key=\(window.isKeyWindow) frame=\(window.frame.debugDescription)"
            )
        }
    }

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
            NSApp.setActivationPolicy(.accessory)
        }

        return controller
    }
}
