import AppKit
import SwiftUI

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        setupWindow()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWindow() {
        guard let window = window else { return }

        window.title = "MouseFlow Settings"
        window.toolbarStyle = .unified

        // Make it behave like a regular app window with proper Spaces support
        window.collectionBehavior = [.managed, .participatesInCycle]

        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("MouseFlowSettingsWindow")

        let settingsView = SettingsView()
        let hostingView = NSHostingView(rootView: settingsView)
        window.contentView = hostingView

        // Center on first open; after that, restore wherever the user last put it.
        window.center()
        window.setFrameAutosaveName("MouseFlowSettingsWindow")
    }

    /// Shows the Settings window, switching to `tab` when given.
    func showWindow(tab: SettingsTab? = nil) {
        if let tab {
            SettingsNavigation.shared.selectedTab = tab
        }

        // The app stays an accessory app (no Dock icon) while Settings is open. A regular app can't
        // show its menus over another app's full-screen Space, so pickers would open invisibly there.
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Force window to front after activation
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }
}
