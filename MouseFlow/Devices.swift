import CoreGraphics
import Foundation

// MARK: - Device

/// A pointing device and its HID service. Its pointer properties read and write the
/// service's dynamic HID properties (IOHID calls).
final class Device {
    enum Category: Equatable {
        case mouse
        case trackpad
        case unknown
    }

    let name: String
    let category: Category
    let registryID: UInt64?
    let service: AnyObject?

    // MARK: - Pointer Properties

    static let fallbackPointerResolution = 400.0
    static let fallbackPointerAcceleration = 0.6875

    private(set) lazy var initialPointerResolution: Double = {
        pointerResolution ?? Self.fallbackPointerResolution
    }()

    init(
        name: String,
        category: Category,
        registryID: UInt64?,
        service: AnyObject? = nil
    ) {
        self.name = name
        self.category = category
        self.registryID = registryID
        self.service = service
    }

    private func getDynamicProperty<T>(_ key: String) -> T? {
        guard let service else { return nil }
        guard let valueRef = IOHIDServiceClientCopyProperty(service, key as CFString)?.takeRetainedValue() else {
            return nil
        }
        return valueRef as? T
    }

    @discardableResult
    private func setDynamicProperty<T>(_ value: T, forKey key: String) -> Bool {
        guard let service else { return false }
        let propertyValue = value as AnyObject
        guard !(propertyValue is NSNull) else { return false }
        return IOHIDServiceClientSetProperty(service, key as CFString, propertyValue).boolValue
    }

    func getDynamicPropertyIOFixed(_ key: String) -> Double? {
        (getDynamicProperty(key) as NSNumber?).map { Double($0.int32Value) / 65536.0 }
    }

    @discardableResult
    func setDynamicPropertyIOFixed(_ value: Double?, forKey key: String) -> Bool {
        guard let value else { return false }
        let fixed = Int32(value * 65536.0)
        return setDynamicProperty(fixed as NSNumber, forKey: key)
    }

    var pointerAccelerationType: String? {
        if let type = getDynamicProperty("HIDPointerAccelerationType") as String? {
            return type
        }
        if (getDynamicProperty("HIDPointerAcceleration") as NSNumber?) != nil {
            return "HIDPointerAcceleration"
        }
        return "HIDMouseAcceleration"
    }

    var useLinearScalingMouseAcceleration: Int? {
        get {
            if let num: NSNumber = getDynamicProperty("HIDUseLinearScalingMouseAcceleration") {
                return num.intValue
            }
            if let val: Int = getDynamicProperty("HIDUseLinearScalingMouseAcceleration") {
                return val
            }
            return nil
        }
        set {
            guard let newValue else { return }
            setDynamicProperty(newValue as NSNumber, forKey: "HIDUseLinearScalingMouseAcceleration")
        }
    }

    var disablePointerAcceleration: Bool? {
        get {
            useLinearScalingMouseAcceleration.map { $0 != 0 }
        }
        set {
            guard let newValue else { return }
            useLinearScalingMouseAcceleration = newValue ? 1 : 0
        }
    }

    var pointerAcceleration: Double? {
        get {
            getDynamicPropertyIOFixed(pointerAccelerationType ?? "HIDMouseAcceleration")
        }
        set {
            setDynamicPropertyIOFixed(
                newValue.map { $0 == -1 ? $0 : min(max($0, 0), 40) },
                forKey: pointerAccelerationType ?? "HIDMouseAcceleration"
            )
        }
    }

    var pointerResolution: Double? {
        get { getDynamicPropertyIOFixed("HIDPointerResolution") }
        set {
            let clamped = newValue.map { min(max($0, 10), 1995) }
            let success = setDynamicPropertyIOFixed(clamped, forKey: "HIDPointerResolution")
            if !success {
                NSLog("[MouseFlow] Failed to set HIDPointerResolution on device %@", name)
            }
            // Reapply an available acceleration value to make pointerResolution take effect.
            let accelerationToReapply = pointerAcceleration ?? Self.fallbackPointerAcceleration
            pointerAcceleration = accelerationToReapply
        }
    }
}

// MARK: - DeviceRegistry

/// Knows the connected pointing devices and which one sent a CGEvent (by its IOHID sender ID).
/// Thread-safe: the event tap looks devices up from its own thread while pointer speed refreshes
/// the list from its queue. `lock` only guards the dictionaries and is never held across IOHID calls.
final class DeviceRegistry {
    static let shared: DeviceRegistry = DeviceRegistry(onMouseDiscovered: { PointerSpeedController.shared.mouseDiscovered($0) })

    private static let appleVendorIDs = Set([0x004C, 0x05AC])
    private static let appleMagicMouseProductIDs = Set([0x0269, 0x030D])
    private static let appleMagicTrackpadProductIDs = Set([0x0265, 0x030E])
    private static let appleBuiltInTrackpadProductIDs = Set([0x0273, 0x0276, 0x0278, 0x0340])

    private let client: AnyObject?
    /// Called when an event lookup sees a mouse for the first time. Never called from `refresh()`.
    private let onMouseDiscovered: (Device) -> Void

    private let lock = NSLock()
    /// Devices by registry ID, which is also the sender ID of their events.
    private var devices = [UInt64: Device]()
    /// Sender IDs that matched no HID service. Lookups skip them until the next refresh,
    /// so an unidentifiable sender doesn't re-enumerate every device on each event.
    private var unresolvedSenderIDs = Set<UInt64>()
    /// Mice already passed to `onMouseDiscovered`.
    private var reportedMouseIDs = Set<UInt64>()

    private init(onMouseDiscovered: @escaping (Device) -> Void) {
        self.onMouseDiscovered = onMouseDiscovered
        if let unmanagedClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault) ?? IOHIDEventSystemClientCreateSimpleClient(nil) {
            let client = unmanagedClient.takeRetainedValue()
            // An unscheduled client keeps the service list from when it was created, so a
            // replugged (or re-enumerated after sleep) mouse with a new registry ID would never
            // be found. Scheduling keeps the list live.
            IOHIDEventSystemClientScheduleWithDispatchQueue(client, .main)
            self.client = client
        } else {
            self.client = nil
        }
        refresh()
    }

    /// The connected mice, as of the last refresh or event lookup.
    var mice: [Device] {
        lock.withLock { devices.values.filter { $0.category == .mouse } }
    }

    /// Re-reads the connected pointing devices from the HID event system and returns the mice.
    @discardableResult
    func refresh() -> [Device] {
        guard let client, let unmanagedServices = IOHIDEventSystemClientCopyServices(client) else { return [] }
        let services = unmanagedServices.takeRetainedValue() as NSArray

        var devicesByRegistryID = [UInt64: Device]()
        for serviceObj in services {
            let service = serviceObj as AnyObject
            guard let rawReg = IOHIDServiceClientGetRegistryID(service),
                  let regID = (rawReg as? UInt64) ?? (rawReg as? NSNumber)?.uint64Value else { continue }
            let (isTouchpad, isMouseOrPointer) = Self.conformance(of: service)
            guard isTouchpad || isMouseOrPointer else { continue }

            devicesByRegistryID[regID] = buildDevice(for: service, registryID: regID)
        }

        lock.withLock {
            devices = devicesByRegistryID
            unresolvedSenderIDs.removeAll()
        }
        return devicesByRegistryID.values.filter { $0.category == .mouse }
    }

    /// The device that sent `event`, or nil when it can't be identified (e.g. synthetic events).
    func device(for event: CGEvent) -> Device? {
        guard let unmanaged = CGEventCopyIOHIDEvent(event) else { return nil }
        let senderID = IOHIDEventGetSenderID(unmanaged.takeRetainedValue())
        guard senderID != 0 else { return nil }

        let known = lock.withLock { devices[senderID] }
        guard let device = known ?? discoverDevice(senderID: senderID) else { return nil }
        if device.category == .mouse, lock.withLock({ reportedMouseIDs.insert(senderID).inserted }) {
            onMouseDiscovered(device)
        }
        return device
    }

    /// A system-wide HID property, such as the System Settings tracking speed.
    func systemProperty(_ key: String) -> NSNumber? {
        guard let client else { return nil }
        return IOHIDEventSystemClientCopyProperty(client, key as CFString)?.takeRetainedValue() as? NSNumber
    }

    /// Looks up a sender that appeared since the last refresh. Makes IOHID calls on the caller's
    /// thread, once per new device (or per unresolvable sender until the next refresh).
    private func discoverDevice(senderID: UInt64) -> Device? {
        guard lock.withLock({ !unresolvedSenderIDs.contains(senderID) }) else { return nil }

        if let client, let unmanagedService = IOHIDEventSystemClientCopyServiceForRegistryID(client, senderID) {
            let device = buildDevice(for: unmanagedService.takeRetainedValue(), registryID: senderID)
            lock.withLock { devices[senderID] = device }
            return device
        }

        refresh()
        return lock.withLock {
            if let device = devices[senderID] { return device }
            unresolvedSenderIDs.insert(senderID)
            return nil
        }
    }

    /// Whether the service is a touch pad, and whether it is a mouse or generic pointer.
    private static func conformance(of service: AnyObject) -> (isTouchpad: Bool, isMouseOrPointer: Bool) {
        (
            isTouchpad: IOHIDServiceClientConformsTo(service, 0x0D, 0x05) != 0,
            isMouseOrPointer: IOHIDServiceClientConformsTo(service, 0x01, 0x02) != 0 || IOHIDServiceClientConformsTo(service, 0x01, 0x01) != 0
        )
    }

    private func buildDevice(for service: AnyObject, registryID: UInt64) -> Device {
        let productName = (IOHIDServiceClientCopyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String) ?? "Pointing Device"
        let vendorID = (IOHIDServiceClientCopyProperty(service, "VendorID" as CFString)?.takeRetainedValue() as? NSNumber)?.intValue
        let productID = (IOHIDServiceClientCopyProperty(service, "ProductID" as CFString)?.takeRetainedValue() as? NSNumber)?.intValue

        let (isTouchPad, isMouseOrPointer) = Self.conformance(of: service)

        let category: Device.Category
        if let vendorID, let productID, Self.appleVendorIDs.contains(vendorID), Self.appleMagicMouseProductIDs.contains(productID) {
            category = .mouse
        } else if isTouchPad {
            category = .trackpad
        } else if let vendorID, let productID,
                  Self.appleMagicTrackpadProductIDs.contains(productID) ||
                  (vendorID == 0x05AC && Self.appleBuiltInTrackpadProductIDs.contains(productID)) {
            category = .trackpad
        } else if isMouseOrPointer {
            category = .mouse
        } else {
            category = .unknown
        }

        debugLog("Discovered device: %@, registryID=%llu, category=%@", productName, registryID, String(describing: category))

        return Device(
            name: productName,
            category: category,
            registryID: registryID,
            service: service
        )
    }
}
