// SettingsView.swift

import SwiftUI
import AppKit
import CoreGraphics

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case pointer = "Pointer"
    case scrolling = "Scrolling"
    case buttons = "Mouse Buttons"

    var id: SettingsTab { self }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .pointer: return "cursorarrow.motionlines"
        case .scrolling: return "arrow.up.and.down"
        case .buttons: return "computermouse"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .blue
        case .pointer: return .indigo
        case .scrolling: return .teal
        case .buttons: return .orange
        }
    }
}

/// The selected Settings tab, so the popover can open Settings on a specific tab.
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var selectedTab: SettingsTab = .general
}

struct SettingsView: View {
    @ObservedObject var appState: AppState = AppState.shared
    @ObservedObject private var loginItemManager = LoginItemManager.shared
    @ObservedObject private var navigation = SettingsNavigation.shared
    @State private var hasAccessibility = AccessibilityPermission.isGranted
    @State private var isConfirmingResetAll = false

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, id: \.self, selection: $navigation.selectedTab) { tab in
                NavigationLink(value: tab) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tab.tint.opacity(0.85))
                            .frame(width: 22, height: 22)
                            .overlay {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        Text(tab.rawValue)
                            .font(.system(size: 13))
                        Spacer()
                        if tab == .scrolling {
                            ConflictBadge(count: appState.scrollModifierConflicts.keys.filter { $0 != .preciseSensitivity }.count)
                        } else if tab == .pointer {
                            ConflictBadge(count: appState.scrollModifierConflicts[.preciseSensitivity] == nil ? 0 : 1)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            Form {
                switch navigation.selectedTab {
                case .general:
                    generalSection
                case .pointer:
                    pointerSection
                case .scrolling:
                    scrollingSection
                case .buttons:
                    buttonsSection
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 640, idealWidth: 700, minHeight: 480, idealHeight: 560)
        .onAppear {
            hasAccessibility = AccessibilityPermission.isGranted
            loginItemManager.refresh()
        }
        // Picks up the permission being granted or revoked while the window is open.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            hasAccessibility = AccessibilityPermission.isGranted
        }
    }

    // MARK: - General Section
    private var generalSection: some View {
        Group {
            Section {
                Toggle("Enabled", isOn: $appState.isEnabled)

                Toggle("Launch at Login", isOn: Binding(
                    get: { loginItemManager.isEnabled },
                    set: { newValue in
                        loginItemManager.setEnabled(newValue)
                    }
                ))

                if loginItemManager.requiresApproval {
                    HStack {
                        Text("Requires approval in System Settings.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Open Settings") {
                            loginItemManager.openSystemSettings()
                        }
                        .controlSize(.small)
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MouseFlow")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Customize how your mouse behaves on macOS.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 2)
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility Permission")
                            .font(.system(size: 13, weight: .medium))
                        Text(hasAccessibility ? "MouseFlow is authorized." : "Required. MouseFlow can't change your mouse until this is on.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if hasAccessibility {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 16))
                    } else {
                        Button("Open Settings") {
                            AccessibilityPermission.openSettings()
                        }
                        .controlSize(.small)
                    }
                }
            } header: {
                Text("Permissions")
            }

            Section {
                LabeledContent("App Version", value: "1.0.0")
            } header: {
                Text("About")
            } footer: {
                HStack {
                    Spacer()
                    Button("Reset All Settings…") {
                        isConfirmingResetAll = true
                    }
                    .help("Resets pointer, scrolling, and mouse button settings. Enabled and Launch at Login stay as they are.")
                }
                .padding(.top, 4)
            }
            .confirmationDialog("Reset all MouseFlow settings to their defaults?", isPresented: $isConfirmingResetAll) {
                Button("Reset All Settings", role: .destructive) {
                    appState.resetAllToDefaults()
                }
            } message: {
                Text("Custom shortcuts, apps, URLs, and Shortcuts assigned to mouse buttons will be removed.")
            }
        }
    }

    // MARK: - Pointer Section
    private var pointerSection: some View {
        Group {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Mouse Sensitivity")
                            .font(.system(size: 13))
                        Spacer()
                        Text(String(format: "%.2f×", appState.pointerSensitivity))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Slider(value: $appState.pointerSensitivity, in: 0.5...2.0, step: 0.05)
                }
                .padding(.vertical, 2)
            } header: {
                Text("Mouse Sensitivity")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Sensitivity")
                            .font(.system(size: 13))
                        Spacer()
                        Text(String(format: "%.2f×", appState.precisionSensitivity))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Slider(value: $appState.precisionSensitivity, in: 0.1...1.0, step: 0.05)
                }
                .padding(.vertical, 2)

                scrollModifierRow(.preciseSensitivity, isOn: $appState.preciseSensitivityEnabled, key: $appState.preciseSensitivityKey)
            } header: {
                Text("Precision Mode")
            } footer: {
                Text("Used while you hold the Precision Mode key, or a mouse button set to \"Precision Mode (hold)\" in Mouse Buttons.")
                    .font(.system(size: 11))
            }
        }
    }

    // MARK: - Scrolling Section
    private var scrollingSection: some View {
        Group {
            Section {
                Toggle("Reverse Scroll Direction", isOn: $appState.windowsStyleScrolling)
                    .help("Scrolls the mouse wheel the opposite way to macOS natural scrolling, like on Windows. Trackpads aren't affected.")

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Scroll Speed")
                        Spacer()
                        Text(String(format: "%.2f×", appState.scrollSpeed))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Slider(value: $appState.scrollSpeed, in: 0.5...3.0, step: 0.25)
                }
                .disabled(!appState.smoothScrolling)

                Toggle("Smooth Scrolling", isOn: $appState.smoothScrolling)

                Picker("Smoothness", selection: $appState.smoothness) {
                    ForEach(ScrollSmoothness.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .disabled(!appState.smoothScrolling)
            } header: {
                Text("Direction & Speed")
            }

            Section {
                scrollModifierRow(.horizontal, isOn: $appState.horizontalScrollEnabled, key: $appState.horizontalScrollKey)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Horizontal Speed")
                        Spacer()
                        Text(String(format: "%.2f×", appState.horizontalScrollSpeed))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Slider(value: $appState.horizontalScrollSpeed, in: 0.5...3.0, step: 0.25)
                }
            } header: {
                Text("Horizontal Scrolling")
            } footer: {
                Text("Hold the key while scrolling to scroll sideways. The speed also applies to tilt wheels.")
                    .font(.system(size: 11))
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Lines per Scroll Tick")
                        Spacer()
                        Text("\(Int(appState.scrollLines)) lines")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Slider(value: $appState.scrollLines, in: 1.0...10.0, step: 1.0)
                }

                // "None" in the picker is the Zoom switch being off.
                Picker("Zoom Modifier Key", selection: Binding(
                    get: { appState.zoomEnabled ? appState.zoomModifierKey : "None" },
                    set: { key in
                        if key == "None" {
                            appState.zoomEnabled = false
                        } else {
                            appState.zoomModifierKey = key
                            appState.zoomEnabled = true
                        }
                    }
                )) {
                    ForEach(["None"] + AppState.scrollFeatureKeys, id: \.self) { key in
                        Text(key).tag(key)
                    }
                }

                scrollModifierRow(.fast, isOn: $appState.fastScrollEnabled, key: $appState.fastScrollKey)
            } header: {
                Text("Scroll Modifiers & Precision")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hold a key while scrolling: Zoom pinch-zooms, Fast Scroll scrolls 3× faster. If two features share a key, the one listed first wins (Precision Mode, under Pointer, comes last).")
                        .font(.system(size: 11))
                    HStack {
                        Spacer()
                        Button("Reset to Defaults") {
                            appState.resetScrollingToDefaults()
                        }
                        .help("Resets direction, speed, smoothing, and scroll modifiers to default values.")
                    }
                }
            }
        }
    }

    // MARK: - Mouse Buttons Section
    private var buttonsSection: some View {
        Group {
            Section {
                ForEach(MouseButton.allCases, id: \.self) { button in
                    buttonActionRow(button)
                }
            } header: {
                Text("Button Mappings")
            } footer: {
                Text("Configure actions for physical buttons on your mouse.")
                    .font(.system(size: 11))
            }

            Section {
                Picker("Button", selection: $appState.customShortcutButton) {
                    ForEach(MouseButton.allCases, id: \.self) { button in
                        Text(button.label).tag(button)
                    }
                }

                HStack {
                    Text("Shortcut")
                    Spacer()
                    CustomShortcutRecorder(
                        shortcut: appState[appState.customShortcutButton].customShortcut,
                        onRecord: { newShortcut in
                            appState.setCustomShortcut(newShortcut, for: appState.customShortcutButton)
                        },
                        onClear: {
                            appState.clearCustomShortcut(for: appState.customShortcutButton)
                        }
                    )
                }
            } header: {
                Text("Custom Button Shortcut")
            } footer: {
                Text("Assign a keyboard shortcut to a physical button. When pressed, the shortcut will trigger and the original mouse click will be consumed.")
                    .font(.system(size: 11))
            }
        }
    }

    @ViewBuilder
    private func buttonActionRow(_ button: MouseButton) -> some View {
        let binding = appState[button]
        Picker(button.label, selection: Binding(
            get: { binding.action },
            set: { selectAction($0, for: button) }
        )) {
            ForEach(Array(ButtonAction.groups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    Divider()
                }
                ForEach(group, id: \.self) { action in
                    Text(appState.actionDisplayName(action, for: button)).tag(action)
                }
            }
        }

        switch binding.action {
        case .launchApp:
            launchAppRow(for: button)
        case .openURL:
            textTargetRow(value: binding.openURL, emptyText: "No URL set", buttonTitle: "Set URL…") {
                editURL(for: button)
            }
        case .runShortcut:
            textTargetRow(value: binding.shortcutName, emptyText: "No shortcut set", buttonTitle: "Set Shortcut…") {
                editShortcutName(for: button)
            }
        default:
            EmptyView()
        }
    }

    /// Picker selection: sets the action and asks for its target when the action needs one.
    private func selectAction(_ action: ButtonAction, for button: MouseButton) {
        guard appState[button].action != action else { return }
        appState[button].action = action
        switch action {
        case .launchApp: chooseApp(for: button)
        case .openURL: editURL(for: button)
        case .runShortcut: editShortcutName(for: button)
        default: break
        }
    }

    private func chooseApp(for button: MouseButton) {
        ButtonTargetPrompts.chooseApp { appState.setLaunchApp($0, for: button) }
    }

    private func editURL(for button: MouseButton) {
        ButtonTargetPrompts.askForURL(initialValue: appState[button].openURL ?? "") { appState[button].openURL = $0 }
    }

    private func editShortcutName(for button: MouseButton) {
        ButtonTargetPrompts.askForShortcutName(initialValue: appState[button].shortcutName ?? "") { appState[button].shortcutName = $0 }
    }

    private func textTargetRow(value: String?, emptyText: String, buttonTitle: String, onEdit: @escaping () -> Void) -> some View {
        HStack {
            Text(value ?? emptyText)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(buttonTitle, action: onEdit)
                .font(.system(size: 11))
                .controlSize(.small)
        }
        .padding(.leading, 8)
    }

    /// A scroll modifier feature: name, conflict badge, key picker and on/off switch.
    private func scrollModifierRow(_ feature: ScrollModifierFeature, isOn: Binding<Bool>, key: Binding<String>) -> some View {
        let blockedBy = appState.scrollModifierConflicts[feature]
        return HStack {
            Text(feature.title)
            Spacer()
            if let blockedBy {
                ConflictBadge(count: 1)
                    .help("\(key.wrappedValue) is already used by \(blockedBy.title)")
            }
            Picker(feature.title, selection: key) {
                ForEach(AppState.scrollFeatureKeys, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(!isOn.wrappedValue)
            Toggle(feature.title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private func launchAppRow(for button: MouseButton) -> some View {
        HStack {
            if let app = appState[button].launchApp {
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                        .resizable()
                        .frame(width: 14, height: 14)
                    Text(app.name)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("No app selected")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Choose App…") {
                chooseApp(for: button)
            }
            .font(.system(size: 11))
            .controlSize(.small)
        }
        .padding(.leading, 8)
    }
}

// MARK: - Custom Shortcut Recorder

struct CustomShortcutRecorder: View {
    let shortcut: KeyShortcut?
    let onRecord: (KeyShortcut) -> Void
    let onClear: () -> Void

    @State private var isRecording = false
    @State private var observationToken: ObservationToken?
    @State private var localMonitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                HStack(spacing: 4) {
                    if isRecording {
                        Text("Type shortcut…")
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)
                    } else if let shortcut = shortcut {
                        Text(shortcut.displayString)
                            .fontWeight(.medium)
                    } else {
                        Text("Click to Record")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.clear)
                        )
                )
            }
            .buttonStyle(.plain)

            if !isRecording && shortcut != nil {
                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true

        observationToken = try? EventTap.observe([
            .flagsChanged,
            .keyDown
        ]) { _, event in
            eventReceived(event)
        }

        if observationToken == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { nsEvent in
                let keyCode = CGKeyCode(nsEvent.keyCode)
                var flags = CGEventFlags()
                if nsEvent.modifierFlags.contains(.command) { flags.insert(.maskCommand) }
                if nsEvent.modifierFlags.contains(.shift) { flags.insert(.maskShift) }
                if nsEvent.modifierFlags.contains(.option) { flags.insert(.maskAlternate) }
                if nsEvent.modifierFlags.contains(.control) { flags.insert(.maskControl) }

                if keyCode == 0x35 && flags.isEmpty {
                    stopRecording()
                    return nil
                }

                let shortcut = KeyShortcut(keyCode: keyCode, modifierFlags: flags)
                onRecord(shortcut)
                stopRecording()
                return nil
            }
        }
    }

    private func stopRecording() {
        isRecording = false
        observationToken?.cancel()
        observationToken = nil
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func eventReceived(_ event: CGEvent) -> CGEvent? {
        switch event.type {
        case .flagsChanged:
            // Let modifier changes through so ⌘⌥⌃⇧ keep working in other apps while recording.
            return event

        case .keyDown:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])

            if keyCode == 0x35 && flags.isEmpty {
                DispatchQueue.main.async {
                    self.stopRecording()
                }
                return nil
            }

            let shortcut = KeyShortcut(keyCode: keyCode, modifierFlags: flags)
            DispatchQueue.main.async {
                self.onRecord(shortcut)
                self.stopRecording()
            }
            return nil

        default:
            break
        }

        return nil
    }
}

// MARK: - Conflict Badge

/// Red count badge, like the ones in System Settings and on iPhone. Hidden when the count is zero.
struct ConflictBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(.white)
                .padding(.horizontal, count > 9 ? 5 : 0)
                .frame(minWidth: 18, minHeight: 18)
                .background(Capsule().fill(Color.red))
                .accessibilityLabel("\(count) key conflict\(count == 1 ? "" : "s")")
        }
    }
}
