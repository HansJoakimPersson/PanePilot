import AppKit
import Foundation

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dragSnapController: DragSnapController?
    private var displayLayoutStore: DisplayLayoutStore?

    public override init() {}

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = AppIconProvider.applicationIconImage()
        DebugLogger.shared.info("PanePilot app launched.")

        let store = DisplayLayoutStore(layouts: RegionLayouts.all)
        store.refreshConnectedDisplays()
        displayLayoutStore = store

        let dragController = DragSnapController(
            permissions: PermissionManager(),
            screens: ScreenProvider(),
            layoutEngine: LayoutEngine(),
            windowController: WindowController(),
            displayLayoutStore: store
        )
        dragController.setRequiredModifier(AppPreferences.snapModifier)
        dragController.start()
        dragSnapController = dragController
        SettingsWindowPresenter.shared.configure(store: store, dragSnapController: dragController)

        DebugLogger.shared.setEnabled(AppPreferences.debugLoggingEnabled)

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

    private func handleScreenParametersChanged() {
        displayLayoutStore?.refreshConnectedDisplays()
        DebugLogger.shared.info("Screen parameters changed. Display registry refreshed.")
    }

}
