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
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = false
        window.level = .normal

        // Make it behave like a regular app window with proper Spaces support
        window.collectionBehavior = [.managed, .participatesInCycle]

        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = false

        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("MouseFlowSettingsWindow")

        let settingsView = SettingsView()
        let hostingView = NSHostingView(rootView: settingsView)
        window.contentView = hostingView

        window.delegate = self

        // Center on first open; after that, restore wherever the user last put it.
        window.center()
        window.setFrameAutosaveName("MouseFlowSettingsWindow")
    }

    /// Shows the Settings window, switching to `tab` when given.
    func showWindow(tab: SettingsTab? = nil) {
        if let tab {
            SettingsNavigation.shared.selectedTab = tab
        }

        // Ensure window exists
        _ = window

        // Reassert regular window semantics in case any prior state mutated this window.
        window?.level = .normal
        window?.collectionBehavior = [.managed, .participatesInCycle]

        // Promote app to regular activation policy when showing window so it receives key events and scrolling
        NSApp.setActivationPolicy(.regular)

        if window?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            window?.orderFrontRegardless()
            window?.makeKeyAndOrderFront(nil)
            return
        }

        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        // Force window to front after activation
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    override func close() {
        super.close()
        relinquishFocus()
    }

    private func relinquishFocus() {
        window?.orderOut(nil)

        NSApp.setActivationPolicy(.accessory)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        relinquishFocus()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func windowDidResignKey(_ notification: Notification) {
    }
}
