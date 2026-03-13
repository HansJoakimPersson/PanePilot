import AppKit
import Foundation

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dragSnapController: DragSnapController?
    private var displayLayoutStore: DisplayLayoutStore?

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

    // PanePilot lives primarily as a menu-bar utility, so launch in accessory mode and
    // only promote to a regular app while the settings window is visible.
    private func configureApplication() {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = AppIconProvider.applicationIconImage()
        DebugLogger.shared.info("PanePilot app launched.")
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
