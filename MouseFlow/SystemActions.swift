import AppKit

/// System-level actions that mouse buttons can trigger, beyond the Dock/Spaces ones in ButtonActions.swift.
enum SystemActions {
    // MARK: - Media keys

    /// NX_KEYTYPE_* values from IOKit/hidsystem/ev_keymap.h
    enum MediaKey: Int {
        case volumeUp = 0
        case volumeDown = 1
        case mute = 7
        case playPause = 16
        case next = 17
        case previous = 18
    }

    /// Posts a media key press the same way the keyboard's media keys do, so any player responds.
    static func post(_ key: MediaKey) {
        for isDown in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: isDown ? 0xA00 : 0xB00)
            let data1 = (key.rawValue << 16) | ((isDown ? 0xA : 0xB) << 8)
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8, // NX_SUBTYPE_AUX_CONTROL_BUTTONS
                data1: data1,
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - System

    /// Opens Launchpad, or the Apps view that replaced it in macOS 26.
    static func openLaunchpad() {
        let candidates = ["/System/Applications/Apps.app", "/System/Applications/Launchpad.app"]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            NSLog("[MouseFlow] Launchpad/Apps not found")
            return
        }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
    }

    /// Locks the screen with the system shortcut ⌃⌘Q.
    static func lockScreen() {
        simulateKeyShortcut(keyCode: 0x0C, modifierFlags: [.maskControl, .maskCommand])
    }

    /// Opens the Screenshot toolbar (the same one ⇧⌘5 shows).
    static func openScreenshotToolbar() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    // MARK: - URL & Shortcuts

    /// Opens a URL, assuming https:// when no scheme is given.
    static func openURL(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme) else {
            NSLog("[MouseFlow] Invalid URL: %@", trimmed)
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Runs a shortcut from the Shortcuts app by name, in the background.
    static func runShortcut(named name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        do {
            try process.run()
        } catch {
            NSLog("[MouseFlow] Failed to run shortcut %@: %@", name, error.localizedDescription)
        }
    }
}
