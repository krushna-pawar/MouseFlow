import Foundation
import ApplicationServices
import AppKit

/// Unified Accessibility permission manager for MouseFlow.
enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false
        ] as CFDictionary)
    }

    static func prompt() {
        AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true
        ] as CFDictionary)
    }

    /// Explains why the permission is needed before macOS shows its own Accessibility prompt.
    /// Choosing Later skips the system prompt; the app still starts once access is granted.
    static func explainAndPrompt() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "MouseFlow needs Accessibility access"
        alert.informativeText = """
            MouseFlow changes how your mouse scrolls and what its buttons do, so it needs to see \
            and adjust mouse events. macOS only allows this for apps you turn on under \
            Privacy & Security › Accessibility.

            MouseFlow starts working as soon as access is on. It doesn't record or send your input anywhere.
            """
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            prompt()
        }
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func pollUntilGranted(completion: @escaping () -> Void) {
        guard isGranted else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                pollUntilGranted(completion: completion)
            }
            return
        }
        completion()
    }
}
