// PrivateSPI.swift
// Private macOS SPI used by MouseFlow, declared via @_silgen_name.

import CoreGraphics
import Foundation

// MARK: - IOHIDEvent & IOHIDServiceClient Private SPI Declarations

@_silgen_name("CGEventCopyIOHIDEvent")
func CGEventCopyIOHIDEvent(_ event: CGEvent) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventGetFloatValue")
func IOHIDEventGetFloatValue(_ event: AnyObject, _ field: UInt32) -> Double

@_silgen_name("IOHIDEventSetFloatValue")
func IOHIDEventSetFloatValue(_ event: AnyObject, _ field: UInt32, _ value: Double)

@_silgen_name("IOHIDEventGetSenderID")
func IOHIDEventGetSenderID(_ event: AnyObject) -> UInt64

@_silgen_name("IOHIDEventSystemClientCreateSimpleClient")
func IOHIDEventSystemClientCreateSimpleClient(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventSystemClientCreate")
func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventSystemClientCopyProperty")
func IOHIDEventSystemClientCopyProperty(_ client: AnyObject, _ key: CFString) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventSystemClientCopyServices")
func IOHIDEventSystemClientCopyServices(_ client: AnyObject) -> Unmanaged<CFArray>?

@_silgen_name("IOHIDEventSystemClientCopyServiceForRegistryID")
func IOHIDEventSystemClientCopyServiceForRegistryID(_ client: AnyObject, _ regID: UInt64) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventSystemClientScheduleWithDispatchQueue")
func IOHIDEventSystemClientScheduleWithDispatchQueue(_ client: AnyObject, _ queue: DispatchQueue)

@_silgen_name("IOHIDServiceClientGetRegistryID")
func IOHIDServiceClientGetRegistryID(_ service: AnyObject) -> AnyObject?

@_silgen_name("IOHIDServiceClientConformsTo")
func IOHIDServiceClientConformsTo(_ service: AnyObject, _ page: UInt32, _ usage: UInt32) -> Int32

@_silgen_name("IOHIDServiceClientCopyProperty")
func IOHIDServiceClientCopyProperty(_ service: AnyObject, _ key: CFString) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDServiceClientSetProperty")
@discardableResult
func IOHIDServiceClientSetProperty(_ service: AnyObject, _ key: CFString, _ value: AnyObject) -> DarwinBoolean

let kIOHIDEventFieldScrollX: UInt32 = (6 << 16) | 0
let kIOHIDEventFieldScrollY: UInt32 = (6 << 16) | 1

// MARK: - CoreDock & CGS HotKey Private SPIs

@_silgen_name("CoreDockSendNotification")
@discardableResult
func CoreDockSendNotification(_ notification: CFString, _ unknown: Int32) -> CGError

@_silgen_name("CGSGetSymbolicHotKeyValue")
func CGSGetSymbolicHotKeyValue(
    _ hotKey: UInt32,
    _ outKeyEquivalent: UnsafeMutablePointer<UniChar>,
    _ outVirtualKeyCode: UnsafeMutablePointer<UniChar>,
    _ outModifiers: UnsafeMutablePointer<UInt32>
) -> CGError

@_silgen_name("CGSIsSymbolicHotKeyEnabled")
func CGSIsSymbolicHotKeyEnabled(_ hotKey: UInt32) -> DarwinBoolean

@_silgen_name("CGSSetSymbolicHotKeyEnabled")
@discardableResult
func CGSSetSymbolicHotKeyEnabled(_ hotKey: UInt32, _ isEnabled: DarwinBoolean) -> CGError
