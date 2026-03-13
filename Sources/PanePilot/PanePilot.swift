import AppKit
import Foundation
import PanePilotKit
import SwiftUI

@main
struct PanePilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar extra is the primary UI surface; the settings window is opened on demand.
        MenuBarExtra {
            Button("Settings…") {
                SettingsWindowPresenter.shared.show()
            }

            Divider()

            Button("Quit PanePilot") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(nsImage: AppIconProvider.menuBarImage())
        }
        .menuBarExtraStyle(.menu)
    }
}
