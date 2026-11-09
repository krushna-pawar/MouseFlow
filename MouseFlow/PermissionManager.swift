import Foundation
import ApplicationServices
import AppKit
import Combine

/// Unified Accessibility permission manager for MouseFlow.
enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false
        ] as CFDictionary)
    }

    /// Emits the current trust state whenever Accessibility access is turned on or off in System Settings.
    /// macOS posts the notification before the new state is readable, so each check waits a moment.
    static let changes: AnyPublisher<Bool, Never> = DistributedNotificationCenter.default()
        .publisher(for: Notification.Name("com.apple.accessibility.api"))
        .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
        .map { _ in isGranted }
        .share()
        .eraseToAnyPublisher()

    /// Adds MouseFlow to the Accessibility list and opens that page of System Settings,
    /// so turning on its switch is all that's left. Opening the page alone isn't enough:
    /// only macOS's own prompt adds an app to the list.
    static func requestAccess() {
        AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true
        ] as CFDictionary)
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
