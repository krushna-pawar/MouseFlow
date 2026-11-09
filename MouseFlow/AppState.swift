import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // General
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "isEnabled")
            PointerSpeedController.shared.setEnabled(isEnabled)
            syncEventTap()
        }
    }

    // Pointer
    static let defaultPointerSensitivity = 1.0
    static let defaultPrecisionSensitivity = 0.35

    @Published var pointerSensitivity: Double {
        didSet {
            UserDefaults.standard.set(pointerSensitivity, forKey: "pointerSensitivity")
            PointerSpeedController.shared.setSensitivity(pointerSensitivity)
        }
    }

    // Scrolling. Every setting the event tap reads is pushed to it through `tapConfig`
    // (see `tapConfigSync`), so a didSet here only persists the value.
    @Published var windowsStyleScrolling: Bool {
        didSet { UserDefaults.standard.set(windowsStyleScrolling, forKey: "windowsStyleScrolling") }
    }
    @Published var scrollSpeed: Double {
        didSet { UserDefaults.standard.set(scrollSpeed, forKey: "scrollSpeed") }
    }
    @Published var smoothScrolling: Bool {
        didSet { UserDefaults.standard.set(smoothScrolling, forKey: "smoothScrolling") }
    }
    @Published var scrollLines: Double {
        didSet { UserDefaults.standard.set(scrollLines, forKey: "scrollLines") }
    }
    @Published var zoomEnabled: Bool {
        didSet { UserDefaults.standard.set(zoomEnabled, forKey: "zoomEnabled") }
    }
    @Published var zoomModifierKey: String {
        didSet { UserDefaults.standard.set(zoomModifierKey, forKey: "zoomModifierKey") }
    }
    @Published var horizontalScrollEnabled: Bool {
        didSet { UserDefaults.standard.set(horizontalScrollEnabled, forKey: "horizontalScrollEnabled") }
    }
    @Published var horizontalScrollKey: String {
        didSet { UserDefaults.standard.set(horizontalScrollKey, forKey: "horizontalScrollKey") }
    }
    @Published var horizontalScrollSpeed: Double {
        didSet { UserDefaults.standard.set(horizontalScrollSpeed, forKey: "horizontalScrollSpeed") }
    }
    @Published var fastScrollEnabled: Bool {
        didSet { UserDefaults.standard.set(fastScrollEnabled, forKey: "fastScrollEnabled") }
    }
    @Published var fastScrollKey: String {
        didSet { UserDefaults.standard.set(fastScrollKey, forKey: "fastScrollKey") }
    }
    @Published var preciseSensitivityEnabled: Bool {
        didSet { UserDefaults.standard.set(preciseSensitivityEnabled, forKey: "preciseSensitivityEnabled") }
    }
    @Published var preciseSensitivityKey: String {
        didSet { UserDefaults.standard.set(preciseSensitivityKey, forKey: "preciseSensitivityKey") }
    }
    @Published var smoothness: ScrollSmoothness {
        didSet { UserDefaults.standard.set(smoothness.rawValue, forKey: "smoothness") }
    }

    // Precision mode
    @Published var precisionSensitivity: Double {
        didSet {
            UserDefaults.standard.set(precisionSensitivity, forKey: "precisionSensitivity")
            PointerSpeedController.shared.setPrecisionSensitivity(precisionSensitivity)
        }
    }

    // Mouse Buttons
    @Published var buttons: [MouseButton: ButtonBinding] {
        didSet {
            for button in MouseButton.allCases where buttons[button] != oldValue[button] {
                self[button].save(for: button, to: .standard)
            }
        }
    }
    @Published var customShortcutButton: MouseButton = .mb3

    /// A button's binding; `buttons` always holds every button.
    subscript(button: MouseButton) -> ButtonBinding {
        get { buttons[button] ?? ButtonBinding(action: button.defaultAction) }
        set { buttons[button] = newValue }
    }

    private static var defaultButtons: [MouseButton: ButtonBinding] {
        Dictionary(uniqueKeysWithValues: MouseButton.allCases.map { ($0, ButtonBinding(action: $0.defaultAction)) })
    }

    /// Keys selectable for the horizontal/fast/precise-sensitivity modifiers (each has its own on/off toggle).
    static let scrollFeatureKeys = ["Command", "Option", "Control", "Shift"]

    /// Blocked scroll modifier features, each mapped to the feature that already uses its key.
    var scrollModifierConflicts: [ScrollModifierFeature: ScrollModifierFeature] {
        ScrollModifiers.conflicts(tapConfig.scrollModifierConfigs)
    }

    /// Sets the app a button launches and selects Launch App for it.
    func setLaunchApp(_ target: LaunchAppTarget, for button: MouseButton) {
        self[button].launchApp = target
        self[button].action = .launchApp
        debugLog("launchApp set for %@ -> %@ (%@)", button.label, target.name, target.path)
    }

    func setCustomShortcut(_ shortcut: KeyShortcut, for button: MouseButton) {
        self[button].customShortcut = shortcut
        self[button].action = .customShortcut
        debugLog("customShortcut set for %@ -> %@", button.label, shortcut.displayString)
    }

    func clearCustomShortcut(for button: MouseButton) {
        self[button].customShortcut = nil
        if self[button].action == .customShortcut {
            self[button].action = .none
        }
        debugLog("customShortcut cleared for %@", button.label)
    }

    func actionDisplayName(_ action: ButtonAction, for button: MouseButton) -> String {
        let binding = self[button]
        switch action {
        case .customShortcut:
            return binding.customShortcut.map { "Custom Shortcut (\($0.displayString))" } ?? action.rawValue
        case .openURL:
            return binding.openURL.map { "Open URL (\($0))" } ?? "Open URL (Set URL…)"
        case .runShortcut:
            return binding.shortcutName.map { "Run Shortcut (\($0))" } ?? "Run Shortcut (Set Name…)"
        case .launchApp:
            return binding.launchApp.map { "Launch App (\($0.name))" } ?? "Launch App (Choose…)"
        case .macro:
            return binding.macro.isEmpty ? "Macro (Record…)" : "Macro (\(Macro.stepCount(binding.macro)))"
        default:
            return action.rawValue
        }
    }

    // MARK: - Event tap config

    /// Everything the event tap reads, built from the current settings.
    private var tapConfig: TapConfig {
        TapConfig(
            scrollSpeed: scrollSpeed,
            windowsStyleScrolling: windowsStyleScrolling,
            smoothScrolling: smoothScrolling,
            smoothness: smoothness,
            scrollLines: scrollLines,
            zoomEnabled: zoomEnabled,
            zoomModifierKey: zoomModifierKey,
            horizontalScrollEnabled: horizontalScrollEnabled,
            horizontalScrollKey: horizontalScrollKey,
            horizontalScrollSpeed: horizontalScrollSpeed,
            fastScrollEnabled: fastScrollEnabled,
            fastScrollKey: fastScrollKey,
            preciseSensitivityEnabled: preciseSensitivityEnabled,
            preciseSensitivityKey: preciseSensitivityKey,
            buttons: Dictionary(uniqueKeysWithValues: buttons.map { ($0.key.rawNumber, $0.value) })
        )
    }

    /// Pushes `tapConfig` to the event tap after any published change.
    private var tapConfigSync: AnyCancellable?

    private func pushTapConfig() {
        GlobalEventTap.shared.apply(tapConfig)
    }

    init() {
        let defaults = UserDefaults.standard
        let tap = TapConfig() // scroll defaults

        self.isEnabled = defaults.object(forKey: "isEnabled") as? Bool ?? true
        self.pointerSensitivity = defaults.object(forKey: "pointerSensitivity") as? Double ?? Self.defaultPointerSensitivity
        self.precisionSensitivity = defaults.object(forKey: "precisionSensitivity") as? Double ?? Self.defaultPrecisionSensitivity

        self.windowsStyleScrolling = defaults.object(forKey: "windowsStyleScrolling") as? Bool ?? tap.windowsStyleScrolling
        self.scrollSpeed = defaults.object(forKey: "scrollSpeed") as? Double ?? tap.scrollSpeed
        self.smoothScrolling = defaults.object(forKey: "smoothScrolling") as? Bool ?? tap.smoothScrolling
        self.scrollLines = defaults.object(forKey: "scrollLines") as? Double ?? tap.scrollLines
        // Older versions turned Zoom off by saving the key as "None".
        let storedZoomKey = defaults.string(forKey: "zoomModifierKey") ?? tap.zoomModifierKey
        self.zoomEnabled = defaults.object(forKey: "zoomEnabled") as? Bool ?? (storedZoomKey != "None")
        self.zoomModifierKey = storedZoomKey == "None" ? tap.zoomModifierKey : storedZoomKey
        self.horizontalScrollEnabled = defaults.object(forKey: "horizontalScrollEnabled") as? Bool ?? tap.horizontalScrollEnabled
        self.horizontalScrollKey = defaults.string(forKey: "horizontalScrollKey") ?? tap.horizontalScrollKey
        self.horizontalScrollSpeed = defaults.object(forKey: "horizontalScrollSpeed") as? Double ?? tap.horizontalScrollSpeed
        self.fastScrollEnabled = defaults.object(forKey: "fastScrollEnabled") as? Bool ?? tap.fastScrollEnabled
        self.fastScrollKey = defaults.string(forKey: "fastScrollKey") ?? tap.fastScrollKey
        self.preciseSensitivityEnabled = defaults.object(forKey: "preciseSensitivityEnabled") as? Bool ?? tap.preciseSensitivityEnabled
        self.preciseSensitivityKey = defaults.string(forKey: "preciseSensitivityKey") ?? tap.preciseSensitivityKey
        self.smoothness = defaults.string(forKey: "smoothness").flatMap(ScrollSmoothness.init(rawValue:)) ?? tap.smoothness

        self.buttons = Dictionary(uniqueKeysWithValues: MouseButton.allCases.map { ($0, ButtonBinding.load(for: $0, from: defaults)) })

        pushTapConfig()
        // objectWillChange fires before the new value is stored, so push on the next main-queue turn.
        tapConfigSync = objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.pushTapConfig() }

        PointerSpeedController.shared.setPrecisionSensitivity(precisionSensitivity)
        PointerSpeedController.shared.setSensitivity(pointerSensitivity)
        // Also undoes leftover pointer changes if MouseFlow didn't quit cleanly while disabled.
        PointerSpeedController.shared.setEnabled(isEnabled)
    }

    /// Resets all scrolling settings to their default values.
    func resetScrollingToDefaults() {
        let tap = TapConfig()
        windowsStyleScrolling = tap.windowsStyleScrolling
        scrollSpeed = tap.scrollSpeed
        smoothScrolling = tap.smoothScrolling
        scrollLines = tap.scrollLines
        zoomEnabled = tap.zoomEnabled
        zoomModifierKey = tap.zoomModifierKey
        horizontalScrollEnabled = tap.horizontalScrollEnabled
        horizontalScrollKey = tap.horizontalScrollKey
        horizontalScrollSpeed = tap.horizontalScrollSpeed
        fastScrollEnabled = tap.fastScrollEnabled
        fastScrollKey = tap.fastScrollKey
        smoothness = tap.smoothness
        debugLog("resetScrollingToDefaults called")
    }

    /// Resets pointer settings to their default values.
    func resetPointerToDefaults() {
        let tap = TapConfig()
        pointerSensitivity = Self.defaultPointerSensitivity
        precisionSensitivity = Self.defaultPrecisionSensitivity
        preciseSensitivityEnabled = tap.preciseSensitivityEnabled
        preciseSensitivityKey = tap.preciseSensitivityKey
    }

    /// Resets button mappings and clears their shortcuts, apps, URLs, Shortcuts names, and macros.
    func resetButtonsToDefaults() {
        buttons = Self.defaultButtons
    }

    /// Resets every pointer, scrolling, and button setting. Enabled and Launch at Login are kept.
    func resetAllToDefaults() {
        resetPointerToDefaults()
        resetScrollingToDefaults()
        resetButtonsToDefaults()
        debugLog("resetAllToDefaults called")
    }

    /// Stops the tap when Accessibility access is turned off and starts it again when it's turned back on.
    private var accessibilitySync: AnyCancellable?

    /// Called once from AppDelegate after launch. Starts the event tap if enabled.
    func startEventTapIfNeeded() {
        debugLog("startEventTapIfNeeded called, AccessibilityPermission.isGranted = %d", AccessibilityPermission.isGranted ? 1 : 0)
        accessibilitySync = AccessibilityPermission.changes.sink { [weak self] granted in
            NSLog("[MouseFlow] Accessibility permission %@", granted ? "granted" : "revoked")
            if granted {
                self?.syncEventTap()
            } else {
                GlobalEventTap.shared.stop()
            }
        }
        if AccessibilityPermission.isGranted {
            syncEventTap()
        } else {
            debugLog("Requesting accessibility prompt and polling...")
            AccessibilityPermission.explainAndPrompt()
            AccessibilityPermission.pollUntilGranted { [weak self] in
                NSLog("[MouseFlow] Accessibility permission granted! Syncing event tap...")
                self?.syncEventTap()
            }
        }
    }

    private func syncEventTap() {
        debugLog("syncEventTap called: isEnabled=%d", isEnabled ? 1 : 0)
        pushTapConfig()
        GlobalEventTap.shared.isEnabled = isEnabled
        if isEnabled {
            GlobalEventTap.shared.start()
        } else {
            GlobalEventTap.shared.stop()
        }
    }
}
