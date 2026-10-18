// ButtonActions.swift

import AppKit

// MARK: - Navigation Gesture & Click Simulation

extension CGMouseButton {
    static let back = CGMouseButton(rawValue: 3)!
    static let forward = CGMouseButton(rawValue: 4)!

    func fixedCGEventType(of eventType: CGEventType) -> CGEventType {
        func fixed(of type: CGEventType, _ l: CGEventType, _ r: CGEventType, _ o: CGEventType) -> CGEventType {
            guard type == l || type == r || type == o else {
                return type
            }
            return self == .left ? l : self == .right ? r : o
        }

        var eventType = eventType
        eventType = fixed(of: eventType, .leftMouseDown, .rightMouseDown, .otherMouseDown)
        eventType = fixed(of: eventType, .leftMouseUp, .rightMouseUp, .otherMouseUp)
        eventType = fixed(of: eventType, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged)
        return eventType
    }
}

private let navigationSwipeBundleIncludes = [
    "com.apple.*",
    "com.binarynights.ForkLift*",
    "org.mozilla.firefox",
    "com.operasoftware.Opera"
]

private func supportsNavigationSwipe(bundleIdentifier: String?) -> Bool {
    guard let bundleIdentifier else { return false }
    return navigationSwipeBundleIncludes.contains { pattern in
        if pattern.hasSuffix("*") {
            return bundleIdentifier.hasPrefix(pattern.dropLast())
        }
        return bundleIdentifier == pattern
    }
}

private func postMouseButtonAction(mouseButton: CGMouseButton) {
    if supportsNavigationSwipe(bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) {
        let direction: IOHIDSwipeMask = (mouseButton == .back) ? .swipeLeft : .swipeRight
        if let gesture = GestureEvent(direction: direction) {
            gesture.post(tap: .cgSessionEventTap)
            return
        }
    }

    postClickEvent(mouseButton: mouseButton)
}

private func postClickEvent(mouseButton: CGMouseButton) {
    guard let location = CGEvent(source: nil)?.location else { return }

    guard let mouseDownEvent = CGEvent(
        mouseEventSource: nil,
        mouseType: mouseButton.fixedCGEventType(of: .leftMouseDown),
        mouseCursorPosition: location,
        mouseButton: mouseButton
    ),
    let mouseUpEvent = CGEvent(
        mouseEventSource: nil,
        mouseType: mouseButton.fixedCGEventType(of: .leftMouseUp),
        mouseCursorPosition: location,
        mouseButton: mouseButton
    ) else {
        return
    }

    mouseDownEvent.isMouseFlowSyntheticEvent = true
    mouseUpEvent.isMouseFlowSyntheticEvent = true

    mouseDownEvent.post(tap: .cgSessionEventTap)
    mouseUpEvent.post(tap: .cgSessionEventTap)
}

// MARK: - ButtonActionExecutor

final class ButtonActionExecutor {
    static let shared = ButtonActionExecutor()

    /// Runs the binding's action on the main queue. `binding` is the event's config snapshot,
    /// so the action and its target always match.
    func execute(_ binding: ButtonBinding) {
        DispatchQueue.main.async {
            switch binding.action {
            case .launchApp:
                if let target = binding.launchApp {
                    debugLog("Launching app %@ (%@)", target.name, target.path)
                    let url = URL(fileURLWithPath: target.path)
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                        if let error = error {
                            NSLog("[MouseFlow] openApplication failed for %@: %@, falling back to open()", target.path, error.localizedDescription)
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            case .customShortcut:
                if let shortcut = binding.customShortcut {
                    debugLog("Executing custom shortcut %@", shortcut.displayString)
                    simulateKeyShortcut(keyCode: shortcut.keyCode, modifierFlags: shortcut.modifierFlags)
                }
            case .macro:
                if let steps = binding.macro { MacroPlayer.shared.play(steps) }
            case .openURL:
                if let url = binding.openURL { SystemActions.openURL(url) }
            case .runShortcut:
                if let name = binding.shortcutName { SystemActions.runShortcut(named: name) }
            case .previousDesktop: postSymbolicHotKey(.spaceLeft)
            case .nextDesktop: postSymbolicHotKey(.spaceRight)
            case .missionControl: CoreDockSendNotification("com.apple.expose.awake" as CFString, 0)
            case .appExpose: CoreDockSendNotification("com.apple.expose.front.awake" as CFString, 0)
            case .showDesktop: CoreDockSendNotification("com.apple.showdesktop.awake" as CFString, 0)
            case .launchpad: SystemActions.openLaunchpad()
            case .back: postMouseButtonAction(mouseButton: .back)
            case .forward: postMouseButtonAction(mouseButton: .forward)
            case .copy: simulateKeyShortcut(keyCode: 0x08, modifierFlags: .maskCommand)
            case .paste: simulateKeyShortcut(keyCode: 0x09, modifierFlags: .maskCommand)
            case .escape: simulateKeyShortcut(keyCode: 0x35, modifierFlags: [])
            case .playPause: SystemActions.post(.playPause)
            case .nextTrack: SystemActions.post(.next)
            case .previousTrack: SystemActions.post(.previous)
            case .volumeUp: SystemActions.post(.volumeUp)
            case .volumeDown: SystemActions.post(.volumeDown)
            case .mute: SystemActions.post(.mute)
            case .lockScreen: SystemActions.lockScreen()
            case .screenshot: SystemActions.openScreenshotToolbar()
            case .none, .precisionModeHold:
                break // handled (or ignored) in the tap
            }
        }
    }
}
