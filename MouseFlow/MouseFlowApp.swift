import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        AppState.shared.startEventTapIfNeeded()

        if CommandLine.arguments.contains("--settings") {
            SettingsWindowController.shared.showWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Leave the mouse on the normal macOS speed and acceleration after quitting.
        PointerSpeedController.shared.restoreSystemSettings()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct MouseFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            ContentView(appState: appState)
        } label: {
            Image(systemName: appState.isEnabled ? "computermouse.fill" : "computermouse")
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    SettingsWindowController.shared.showWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
