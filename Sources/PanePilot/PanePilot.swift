import AppKit
import Foundation
import PanePilotKit
import SwiftUI

/// App entry point.
///
/// PanePilot lives entirely in the menu bar — it has no dock presence and no persistent window.
/// The menu bar extra is the only SwiftUI surface; all other UI is AppKit and lives in
/// `PanePilotKit`. `AppDelegate` handles lifecycle, accessibility, and snap monitoring.
@main
struct PanePilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar extra is the only UI entry point. Settings open on demand via AppKit.
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
