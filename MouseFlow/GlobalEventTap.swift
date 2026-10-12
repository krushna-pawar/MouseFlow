// GlobalEventTap.swift

import CoreGraphics
import Foundation
import os.log

// MARK: - GlobalEventTap Settings

/// Everything the event tap reads, as one value. AppState builds it from its settings and the tap
/// swaps it in atomically, so each event sees one consistent snapshot.
/// The property defaults are the app's scroll defaults (AppState uses them for loading and reset).
struct TapConfig {
    var scrollSpeed = 1.0
    var windowsStyleScrolling = true
    var smoothScrolling = true
    var smoothness: ScrollSmoothness = .medium
    var scrollLines = 3.0
    var zoomEnabled = true
    var zoomModifierKey = "Control"
    var horizontalScrollEnabled = false
    var horizontalScrollKey = "Shift"
    var horizontalScrollSpeed = 1.0
    var fastScrollEnabled = false
    var fastScrollKey = "Option"
    var preciseSensitivityEnabled = false
    var preciseSensitivityKey = "Command"

    /// Keyed by raw CGEvent button number (see `MouseButton.rawNumber`).
    var buttons: [Int64: ButtonBinding] = [:]

    var scrollModifierConfigs: [ScrollModifierConfig] {
        [
            ScrollModifierConfig(feature: .zoom, isEnabled: zoomEnabled, key: zoomModifierKey),
            ScrollModifierConfig(feature: .horizontal, isEnabled: horizontalScrollEnabled, key: horizontalScrollKey),
            ScrollModifierConfig(feature: .fast, isEnabled: fastScrollEnabled, key: fastScrollKey),
            ScrollModifierConfig(feature: .preciseSensitivity, isEnabled: preciseSensitivityEnabled, key: preciseSensitivityKey)
        ]
    }
}

/// Thread-safe holder for the config read by the event tap callback.
final class EventTapSettings {
    private let lock = NSLock()
    private var _isEnabled = true
    private var _config = TapConfig()

    var isEnabled: Bool {
        get { lock.withLock { _isEnabled } }
        set { lock.withLock { _isEnabled = newValue } }
    }

    var config: TapConfig {
        get { lock.withLock { _config } }
        set { lock.withLock { _config = newValue } }
    }
}

// MARK: - GlobalEventTap

/// The system-wide event tap. Its callback takes one `TapConfig` snapshot per event and routes
/// scroll events to `ScrollPipeline`, modifier changes to zoom and precision mode, and mouse
/// buttons to their bound actions.
final class GlobalEventTap {
    static let shared = GlobalEventTap()

    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "GlobalEventTap")

    private var observationToken: ObservationToken?
    private let eventThread = EventThread.shared

    /// Thread-safe settings container.
    let settings = EventTapSettings()

    var isEnabled: Bool {
        get { settings.isEnabled }
        set { settings.isEnabled = newValue }
    }

    /// Swaps in a new config; each event reads one consistent snapshot of it.
    func apply(_ config: TapConfig) {
        settings.config = config
        if !config.smoothScrolling {
            scrollPipeline.reset()
        }
    }

    init() {}

    // MARK: - Event Callback

    private func handleEvent(_ proxy: CGEventTapProxy, _ event: CGEvent) -> CGEvent? {
        guard settings.isEnabled else { return event }
        let config = settings.config

        switch event.type {
        case .scrollWheel:
            return handleScrollWheel(event, config: config)

        case .flagsChanged:
            let held = ScrollModifiers.activeFeatures(config.scrollModifierConfigs, flags: event.flags)
            scrollPipeline.modifiersChanged(held)
            PointerSpeedController.shared.setPrecisionHeld(held.contains(.preciseSensitivity), source: .modifierKey)
            return event

        case .leftMouseDown, .leftMouseUp, .leftMouseDragged,
             .rightMouseDown, .rightMouseUp, .rightMouseDragged,
             .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            return handleMouseButton(event, config: config)

        default:
            return event
        }
    }

    // MARK: - Mouse Button Handling

    private func handleMouseButton(_ event: CGEvent, config: TapConfig) -> CGEvent? {
        if event.isMouseFlowSyntheticEvent {
            return event
        }

        var rawButton = event.getIntegerValueField(.mouseEventButtonNumber)
        if rawButton == 0 && (event.type == .rightMouseDown || event.type == .rightMouseUp || event.type == .rightMouseDragged) {
            rawButton = 1
        }
        guard let binding = config.buttons[rawButton], binding.action != .none else {
            return event
        }

        if binding.action == .precisionModeHold {
            switch event.type {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                PointerSpeedController.shared.setPrecisionHeld(true, source: .button)
            case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                PointerSpeedController.shared.setPrecisionHeld(false, source: .button)
            default:
                break
            }
            return nil
        }

        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            debugLog("%@ → %@", MouseButton(rawNumber: rawButton)?.label ?? "MB\(rawButton)", binding.action.rawValue)
            ButtonActionExecutor.shared.execute(binding)
            return nil

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            debugLog("consumed raw button %lld (up)", rawButton)
            return nil

        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return nil

        default:
            return event
        }
    }

    // MARK: - Scroll Wheel

    private let scrollPipeline = ScrollPipeline()

    /// Scroll events from mice go through the scroll pipeline. Trackpads, unknown devices,
    /// and MouseFlow's own synthetic events pass through untouched.
    private func handleScrollWheel(_ event: CGEvent, config: TapConfig) -> CGEvent? {
        guard !event.isMouseFlowSyntheticEvent,
              DeviceRegistry.shared.device(for: event)?.category == .mouse else {
            return event
        }
        return scrollPipeline.process(event, config: config)
    }

    // MARK: - Lifecycle

    private static let observedEventTypes: [CGEventType] = [
        .scrollWheel,
        .flagsChanged,
        .leftMouseDown,
        .leftMouseUp,
        .leftMouseDragged,
        .rightMouseDown,
        .rightMouseUp,
        .rightMouseDragged,
        .otherMouseDown,
        .otherMouseUp,
        .otherMouseDragged
    ]

    func start() {
        guard observationToken == nil else {
            debugLog("GlobalEventTap.start: already started")
            return
        }

        guard AccessibilityPermission.enabled else {
            NSLog("[MouseFlow] GlobalEventTap.start: Accessibility permission not granted")
            return
        }

        debugLog("GlobalEventTap.start: initializing DeviceRegistry and starting eventThread...")
        _ = DeviceRegistry.shared
        eventThread.start()

        guard let observationResult = eventThread.performAndWait({ [self] in
            Result {
                try EventTap.observe(
                    Self.observedEventTypes,
                    onInvalidated: { [weak self] in
                        DispatchQueue.main.async { self?.restart() }
                    }
                ) { [weak self] proxy, event in
                    guard let self else { return event }
                    return self.handleEvent(proxy, event)
                }
            }
        }) else {
            NSLog("[MouseFlow] EventThread performAndWait returned nil")
            eventThread.stop()
            return
        }

        switch observationResult {
        case let .success(token):
            observationToken = token
            os_log("GlobalEventTap successfully started!", log: Self.log, type: .default)
            NSLog("[MouseFlow] GlobalEventTap successfully started!")
        case let .failure(error):
            eventThread.stop()
            os_log("Failed to start GlobalEventTap: %{public}@", log: Self.log, type: .error, String(describing: error))
            NSLog("[MouseFlow] Failed to start GlobalEventTap: %@", String(describing: error))
        }
    }

    func stop() {
        observationToken?.cancel()
        observationToken = nil
        eventThread.stop()
        scrollPipeline.reset()
        NSLog("[MouseFlow] GlobalEventTap stopped")
    }

    private func restart() {
        os_log("Restarting GlobalEventTap", log: Self.log, type: .info)
        stop()
        start()
    }
}
