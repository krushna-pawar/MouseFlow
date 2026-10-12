// PointerSpeed.swift

import AppKit
import Foundation
import IOKit

/// Sets the pointer speed of every connected mouse: the Sensitivity setting, the precision
/// sensitivity while precision mode is held, and the System Settings values again when MouseFlow
/// is disabled or quits.
///
/// macOS acceleration is turned off (linear scaling). In that mode `HIDMouseAcceleration` acts as a
/// plain speed multiplier and `HIDPointerResolution` is ignored, so speed is written as the System
/// Settings tracking speed × sensitivity. Mice without linear scaling fall back to pointer resolution.
///
/// All state lives on `queue`, which also makes every HID property write, so callers (including the
/// event tap thread) never wait on IOHID calls.
final class PointerSpeedController {
    static let shared: PointerSpeedController = PointerSpeedController(registry: .shared)

    /// What can hold precision mode on: a "Precision Mode (hold)" button or the Precision Mode key.
    enum PrecisionSource {
        case button
        case modifierKey
    }

    private let registry: DeviceRegistry
    private let queue = DispatchQueue(label: "MouseFlow.PointerSpeed")

    // Only touched on `queue`.
    /// Whether MouseFlow controls pointer speed. Off until AppState turns it on.
    private var isEnabled = false
    private var sensitivity = 1.0
    /// Sensitivity used while precision mode is held.
    private var precisionSensitivity = 0.35
    /// Sources currently holding precision mode; it stays on until all are released.
    private var precisionSources = Set<PrecisionSource>()
    /// Registry IDs of mice that already have the current sensitivity.
    private var configuredMouseIDs = Set<UInt64>()
    /// Pointer resolution of each mouse before MouseFlow changed it (only used without linear scaling).
    private var originalPointerResolutions = [UInt64: Double]()

    // Set up once on init.
    private var deviceNotificationPort: IONotificationPortRef?
    private var wakeObserver: NSObjectProtocol?

    private init(registry: DeviceRegistry) {
        self.registry = registry
        startMonitoringDeviceChanges()
        startMonitoringWake()
    }

    // MARK: - Interface

    /// Turns pointer control on (applies the sensitivity to every mouse) or off (restores macOS settings).
    func setEnabled(_ enabled: Bool) {
        queue.async { [self] in
            isEnabled = enabled
            if enabled {
                syncConnectedMice(reapplyAll: true)
            } else {
                precisionSources.removeAll()
                restoreSystemPointerSettings()
            }
        }
    }

    /// Sets the pointer sensitivity (0.5x to 2.0x).
    func setSensitivity(_ value: Double) {
        queue.async { [self] in
            sensitivity = value
            guard isEnabled else { return }
            let mice = registry.mice
            if mice.isEmpty {
                debugLog("no external mouse available")
            }
            for mouse in mice {
                apply(effectiveSensitivity, to: mouse)
            }
        }
    }

    func setPrecisionSensitivity(_ value: Double) {
        queue.async { [self] in
            precisionSensitivity = value
            guard isEnabled, isPrecisionActive else { return }
            for mouse in registry.mice {
                apply(value, to: mouse)
            }
        }
    }

    /// Switches every mouse to the precision sensitivity while a precision button or key is held.
    func setPrecisionHeld(_ held: Bool, source: PrecisionSource) {
        queue.async { [self] in
            let wasActive = isPrecisionActive
            if held {
                precisionSources.insert(source)
            } else {
                precisionSources.remove(source)
            }
            guard isPrecisionActive != wasActive, isEnabled else { return }
            for mouse in registry.mice {
                apply(effectiveSensitivity, to: mouse)
            }
        }
    }

    /// Called by the registry when an event comes from a mouse it hadn't reported yet.
    func mouseDiscovered(_ mouse: Device) {
        queue.async { [self] in
            guard isEnabled, let id = mouse.registryID, !configuredMouseIDs.contains(id) else { return }
            apply(effectiveSensitivity, to: mouse)
        }
    }

    /// Puts every mouse back on the System Settings pointer speed. Blocks until done, for quitting.
    func restoreSystemSettings() {
        queue.sync { restoreSystemPointerSettings() }
    }

    // MARK: - On `queue`

    private var isPrecisionActive: Bool { !precisionSources.isEmpty }

    /// The sensitivity mice should have right now.
    private var effectiveSensitivity: Double {
        isPrecisionActive ? precisionSensitivity : sensitivity
    }

    /// The user's "Tracking speed" from System Settings, used as the 1.0x baseline.
    private var systemTrackingSpeed: Double {
        let speed = registry.systemProperty("HIDMouseAcceleration").map { Double($0.int32Value) / 65536.0 }
        guard let speed, speed > 0 else { return Device.fallbackPointerAcceleration }
        return speed
    }

    /// Re-reads the connected devices, forgets unplugged mice, and applies the sensitivity to
    /// mice that don't have it yet (or to all of them when `reapplyAll` is set).
    private func syncConnectedMice(reapplyAll: Bool) {
        let mice = registry.refresh()
        configuredMouseIDs.formIntersection(mice.compactMap(\.registryID))
        if reapplyAll {
            configuredMouseIDs.removeAll()
        }
        guard isEnabled else { return }
        for mouse in mice {
            guard let id = mouse.registryID, !configuredMouseIDs.contains(id) else { continue }
            apply(effectiveSensitivity, to: mouse)
        }
    }

    /// Puts every mouse back on the System Settings pointer speed and acceleration.
    private func restoreSystemPointerSettings() {
        let linearScaling = registry.systemProperty("HIDUseLinearScalingMouseAcceleration")?.intValue
        let trackingSpeed = systemTrackingSpeed
        for mouse in registry.mice {
            if let linearScaling, mouse.useLinearScalingMouseAcceleration != nil {
                mouse.useLinearScalingMouseAcceleration = linearScaling
            }
            mouse.pointerAcceleration = trackingSpeed
            if let id = mouse.registryID, let resolution = originalPointerResolutions[id] {
                mouse.pointerResolution = resolution
            }
        }
        configuredMouseIDs.removeAll()
        originalPointerResolutions.removeAll()
        NSLog("[MouseFlow] restored system pointer settings")
    }

    private func apply(_ sensitivity: Double, to mouse: Device) {
        guard mouse.category == .mouse else { return }

        mouse.disablePointerAcceleration = true
        if mouse.disablePointerAcceleration == true {
            // Linear scaling: macOS ignores HIDPointerResolution here, and the
            // acceleration value becomes a straight speed multiplier.
            mouse.pointerAcceleration = systemTrackingSpeed * sensitivity
        } else {
            // No linear scaling support: -1 turns acceleration off, and the
            // pointer resolution sets the speed.
            mouse.pointerAcceleration = -1
            var baseResolution = mouse.initialPointerResolution
            if let id = mouse.registryID {
                baseResolution = originalPointerResolutions[id] ?? baseResolution
                originalPointerResolutions[id] = baseResolution
            }
            mouse.pointerResolution = min(max(baseResolution / sensitivity, 10.0), 1995.0)
        }
        if let id = mouse.registryID {
            configuredMouseIDs.insert(id)
        }

        debugLog("applying pointer sensitivity %.2fx to %@", sensitivity, mouse.name)
    }

    // MARK: - Device and wake monitoring

    /// Watches IOKit for HID devices being plugged in or removed.
    private func startMonitoringDeviceChanges() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, .main)
        deviceNotificationPort = port

        let callback: IOServiceMatchingCallback = { refcon, iterator in
            // Drain the iterator; this also re-arms the notification.
            while case let service = IOIteratorNext(iterator), service != 0 {
                IOObjectRelease(service)
            }
            guard let refcon else { return }
            let controller = Unmanaged<PointerSpeedController>.fromOpaque(refcon).takeUnretainedValue()
            controller.scheduleDeviceSync()
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notificationType in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port, notificationType, IOServiceMatching("IOHIDEventService"), callback, refcon, &iterator
            )
            guard result == KERN_SUCCESS else { continue }
            // Arm the notification by draining the devices that already exist.
            while case let service = IOIteratorNext(iterator), service != 0 {
                IOObjectRelease(service)
            }
        }
    }

    /// The HID event system can register a new device slightly after IOKit reports it,
    /// so sync once shortly after the change and once more a bit later.
    private func scheduleDeviceSync() {
        for delay in [0.5, 2.0] {
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.syncConnectedMice(reapplyAll: false)
            }
        }
    }

    /// macOS can reset HID pointer properties across sleep, so reapply after waking.
    private func startMonitoringWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            for delay in [1.0, 3.0] {
                self?.queue.asyncAfter(deadline: .now() + delay) {
                    self?.syncConnectedMice(reapplyAll: true)
                }
            }
        }
    }
}
