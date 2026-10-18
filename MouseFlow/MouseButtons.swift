import Foundation

/// A mouse button as Settings names it (by physical label), with the raw CGEvent button number
/// the event tap sees. This is the only place the physical-to-raw mapping lives.
enum MouseButton: CaseIterable, Hashable {
    case left, right, middle, mb3, mb4, mb5, mb6, mb7

    /// Raw CGEvent button number. Physical MB3 reports as raw 4 and MB4 as raw 3.
    var rawNumber: Int64 {
        switch self {
        case .left: return 0
        case .right: return 1
        case .middle: return 2
        case .mb3: return 4
        case .mb4: return 3
        case .mb5: return 5
        case .mb6: return 6
        case .mb7: return 7
        }
    }

    init?(rawNumber: Int64) {
        guard let button = Self.allCases.first(where: { $0.rawNumber == rawNumber }) else { return nil }
        self = button
    }

    var label: String {
        switch self {
        case .left: return "L"
        case .right: return "R"
        case .middle: return "Middle"
        case .mb3: return "MB3"
        case .mb4: return "MB4"
        case .mb5: return "MB5"
        case .mb6: return "MB6"
        case .mb7: return "MB7"
        }
    }

    var defaultAction: ButtonAction {
        switch self {
        case .middle: return .missionControl
        case .mb3: return .previousDesktop
        case .mb4: return .nextDesktop
        default: return .none
        }
    }

    /// UserDefaults key for the action. Historical names: MB3 is "button4Action", MB4 is "button5Action".
    fileprivate var actionDefaultsKey: String {
        switch self {
        case .left: return "leftButtonAction"
        case .right: return "rightButtonAction"
        case .middle: return "middleButtonAction"
        case .mb3: return "button4Action"
        case .mb4: return "button5Action"
        case .mb5: return "button6Action"
        case .mb6: return "button7Action"
        case .mb7: return "button8Action"
        }
    }
}

/// What a mouse button does. Raw values are the persisted names and the picker titles.
enum ButtonAction: String, CaseIterable {
    case none = "None"
    case launchApp = "Launch App"
    case openURL = "Open URL"
    case runShortcut = "Run Shortcut"
    case customShortcut = "Custom Shortcut"
    case macro = "Macro"
    case previousDesktop = "Previous Desktop"
    case nextDesktop = "Next Desktop"
    case missionControl = "Mission Control"
    case appExpose = "App Exposé"
    case showDesktop = "Show Desktop"
    case launchpad = "Launchpad"
    case back = "Back"
    case forward = "Forward"
    case copy = "Copy"
    case paste = "Paste"
    case escape = "Escape"
    case playPause = "Play/Pause"
    case nextTrack = "Next Track"
    case previousTrack = "Previous Track"
    case volumeUp = "Volume Up"
    case volumeDown = "Volume Down"
    case mute = "Mute"
    case lockScreen = "Lock Screen"
    case screenshot = "Screenshot"
    case precisionModeHold = "Precision Mode (hold)"

    /// Actions grouped for the pickers (a divider is shown between groups).
    static let groups: [[ButtonAction]] = [
        [.none],
        [.launchApp, .openURL, .runShortcut, .customShortcut, .macro],
        [.previousDesktop, .nextDesktop, .missionControl, .appExpose, .showDesktop, .launchpad],
        [.back, .forward, .copy, .paste, .escape],
        [.playPause, .nextTrack, .previousTrack, .volumeUp, .volumeDown, .mute],
        [.lockScreen, .screenshot, .precisionModeHold]
    ]
}

/// A button's action and its targets. Targets are kept when the action changes,
/// so switching back to e.g. Open URL restores the URL.
struct ButtonBinding: Equatable {
    var action: ButtonAction
    var launchApp: LaunchAppTarget?
    var openURL: String?
    var shortcutName: String?
    var customShortcut: KeyShortcut?
    var macro: [MacroStep]?

    static func load(for button: MouseButton, from defaults: UserDefaults) -> ButtonBinding {
        let raw = button.rawNumber
        var binding = ButtonBinding(
            action: defaults.string(forKey: button.actionDefaultsKey).flatMap(ButtonAction.init(rawValue:)) ?? button.defaultAction
        )
        binding.launchApp = defaults.data(forKey: "launchApp_\(raw)").flatMap { try? JSONDecoder().decode(LaunchAppTarget.self, from: $0) }
        binding.customShortcut = defaults.data(forKey: "customShortcut_\(raw)").flatMap { try? JSONDecoder().decode(KeyShortcut.self, from: $0) }
        binding.macro = defaults.data(forKey: "macro_\(raw)").flatMap { try? JSONDecoder().decode([MacroStep].self, from: $0) }
        binding.openURL = defaults.string(forKey: "openURL_\(raw)")
        binding.shortcutName = defaults.string(forKey: "runShortcut_\(raw)")
        return binding
    }

    func save(for button: MouseButton, to defaults: UserDefaults) {
        let raw = button.rawNumber
        defaults.set(action.rawValue, forKey: button.actionDefaultsKey)
        defaults.set(launchApp.flatMap { try? JSONEncoder().encode($0) }, forKey: "launchApp_\(raw)")
        defaults.set(customShortcut.flatMap { try? JSONEncoder().encode($0) }, forKey: "customShortcut_\(raw)")
        defaults.set(macro.flatMap { try? JSONEncoder().encode($0) }, forKey: "macro_\(raw)")
        defaults.set(openURL, forKey: "openURL_\(raw)")
        defaults.set(shortcutName, forKey: "runShortcut_\(raw)")
    }
}

// MARK: - LaunchAppTarget

struct LaunchAppTarget: Codable, Equatable {
    var path: String
    var name: String
}
