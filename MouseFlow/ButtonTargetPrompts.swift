import AppKit
import UniformTypeIdentifiers

/// Sheets on the Settings window that ask for a mouse button's target: an app, a URL,
/// or the name of a shortcut from the Shortcuts app.
@MainActor
enum ButtonTargetPrompts {
    static func askForURL(initialValue: String, onSave: @escaping (String) -> Void) {
        askForText(
            title: "Open URL",
            message: "Enter the web address this button should open.",
            placeholder: "https://example.com",
            initialValue: initialValue,
            onSave: onSave
        )
    }

    static func askForShortcutName(initialValue: String, onSave: @escaping (String) -> Void) {
        askForText(
            title: "Run Shortcut",
            message: "Enter the exact name of a shortcut from the Shortcuts app.",
            placeholder: "Shortcut name",
            initialValue: initialValue,
            onSave: onSave
        )
    }

    static func chooseApp(onChoose: @escaping (LaunchAppTarget) -> Void) {
        guard let settingsWindow = frontSettingsWindow() else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        panel.beginSheetModal(for: settingsWindow) { response in
            guard response == .OK, let url = panel.url else { return }
            var name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") {
                name = String(name.dropLast(4))
            }
            onChoose(LaunchAppTarget(path: url.path, name: name))
        }
    }

    /// Asks for one line of text; `onSave` gets the trimmed value unless it is empty or cancelled.
    private static func askForText(
        title: String,
        message: String,
        placeholder: String,
        initialValue: String,
        onSave: @escaping (String) -> Void
    ) {
        guard let settingsWindow = frontSettingsWindow() else { return }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = placeholder
        field.stringValue = initialValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        alert.beginSheetModal(for: settingsWindow) { response in
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard response == .alertFirstButtonReturn, !value.isEmpty else { return }
            onSave(value)
        }
    }

    private static func frontSettingsWindow() -> NSWindow? {
        guard let settingsWindow = SettingsWindowController.shared.window else { return nil }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
        return settingsWindow
    }
}
