// KeySynthesis.swift
// Synthesized key presses: custom shortcuts, symbolic hot keys (desktop switching), key names.

import Carbon
import CoreGraphics
import Foundation

// MARK: - Symbolic Hot Keys

enum SymbolicHotKey: UInt32 {
    case spaceLeft = 79
    case spaceRight = 81
}

private func symbolicHotKeyVirtualKeyCode(keyEquivalent: UniChar, virtualKeyCode: UniChar) -> CGKeyCode? {
    guard virtualKeyCode != 0xFFFF else {
        return nil
    }
    guard virtualKeyCode != 0 || keyEquivalent != 0xFFFF else {
        return nil
    }
    return CGKeyCode(virtualKeyCode)
}

private func waitUntilCGEventsBeingHandled() {
    enum Consts {
        static let magic: Int64 = 10_086
    }

    var seenMark = false

    let callback: CGEventTapCallBack = { _, _, event, refcon in
        if event.getIntegerValueField(.eventSourceUserData) == Consts.magic {
            refcon?.storeBytes(of: true, as: Bool.self)
        }
        return Unmanaged.passUnretained(event)
    }

    guard let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .tailAppendEventTap,
        options: .listenOnly,
        eventsOfInterest: 1 << CGEventType.null.rawValue,
        callback: callback,
        userInfo: &seenMark
    ) else {
        return
    }

    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

    if let mark = CGEvent(source: nil) {
        mark.setIntegerValueField(.eventSourceUserData, value: Consts.magic)
        mark.post(tap: .cgSessionEventTap)
    }
    CGEvent.tapEnable(tap: eventTap, enable: true)

    for _ in 0 ..< 10 {
        let result = CFRunLoopRunInMode(.defaultMode, 0.01, true)
        if seenMark || result == .finished {
            break
        }
    }

    CGEvent.tapEnable(tap: eventTap, enable: false)
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
}

func postSymbolicHotKey(_ hotkey: SymbolicHotKey) {
    let rawHotKey = hotkey.rawValue

    var keyEquivalent: UniChar = 0
    var virtualKeyCode: UniChar = 0
    var modifiers: UInt32 = 0

    let error = CGSGetSymbolicHotKeyValue(
        rawHotKey,
        &keyEquivalent,
        &virtualKeyCode,
        &modifiers
    )
    guard error == .success else {
        return
    }

    guard let virtualKeyCode = symbolicHotKeyVirtualKeyCode(
        keyEquivalent: keyEquivalent,
        virtualKeyCode: virtualKeyCode
    ) else {
        return
    }

    let hotkeyEnabled = CGSIsSymbolicHotKeyEnabled(rawHotKey).boolValue
    if !hotkeyEnabled {
        CGSSetSymbolicHotKeyEnabled(rawHotKey, DarwinBoolean(true))
    }
    defer {
        if !hotkeyEnabled {
            waitUntilCGEventsBeingHandled()
            CGSSetSymbolicHotKeyEnabled(rawHotKey, DarwinBoolean(false))
        }
    }

    simulateKeyShortcut(keyCode: virtualKeyCode, modifierFlags: CGEventFlags(rawValue: UInt64(modifiers)))
}

// MARK: - Hardware-Like Key Event

extension CGEvent {
    static func makeHardwareLikeKeyEvent(virtualKey: CGKeyCode, keyDown: Bool) -> CGEvent? {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown) else {
            return nil
        }

        event.timestamp = CGEventTimestamp(DispatchTime.now().uptimeNanoseconds)
        event.setIntegerValueField(.keyboardEventKeyboardType, value: Int64(source.keyboardType))
        return event
    }
}

// MARK: - KeyShortcut

struct KeyShortcut: Codable, Equatable {
    var keyCode: CGKeyCode
    var modifierFlagsRaw: UInt64
    var displayString: String

    var modifierFlags: CGEventFlags {
        CGEventFlags(rawValue: modifierFlagsRaw)
    }

    init(keyCode: CGKeyCode, modifierFlags: CGEventFlags) {
        self.keyCode = keyCode
        self.modifierFlagsRaw = modifierFlags.rawValue
        self.displayString = Self.displayString(keyCode: keyCode, modifierFlags: modifierFlags)
    }

    static func displayString(keyCode: CGKeyCode, modifierFlags: CGEventFlags) -> String {
        var str = ""
        if modifierFlags.contains(.maskCommand) { str += "⌘" }
        if modifierFlags.contains(.maskAlternate) { str += "⌥" }
        if modifierFlags.contains(.maskControl) { str += "⌃" }
        if modifierFlags.contains(.maskShift) { str += "⇧" }
        str += keyName(for: keyCode)
        return str
    }

    static func keyName(for keyCode: CGKeyCode) -> String {
        switch Int(keyCode) {
        // Arrow keys
        case 0x7B: return "←"
        case 0x7C: return "→"
        case 0x7D: return "↓"
        case 0x7E: return "↑"

        // Special keys
        case 0x24: return "↩"
        case 0x30: return "⇥"
        case 0x31: return "Space"
        case 0x33: return "⌫"
        case 0x35: return "⎋"
        case 0x75: return "⌦"
        case 0x74: return "⇞"
        case 0x79: return "⇟"
        case 0x73: return "↖"
        case 0x77: return "↘"

        // Function keys
        case 0x7A: return "F1"
        case 0x78: return "F2"
        case 0x63: return "F3"
        case 0x76: return "F4"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x6D: return "F10"
        case 0x67: return "F11"
        case 0x6F: return "F12"

        // Standard letters & digits (ANSI fallback)
        case 0x00: return "A"
        case 0x01: return "S"
        case 0x02: return "D"
        case 0x03: return "F"
        case 0x04: return "H"
        case 0x05: return "G"
        case 0x06: return "Z"
        case 0x07: return "X"
        case 0x08: return "C"
        case 0x09: return "V"
        case 0x0B: return "B"
        case 0x0C: return "Q"
        case 0x0D: return "W"
        case 0x0E: return "E"
        case 0x0F: return "R"
        case 0x10: return "Y"
        case 0x11: return "T"
        case 0x12: return "1"
        case 0x13: return "2"
        case 0x14: return "3"
        case 0x15: return "4"
        case 0x16: return "6"
        case 0x17: return "5"
        case 0x18: return "="
        case 0x19: return "9"
        case 0x1A: return "7"
        case 0x1B: return "-"
        case 0x1C: return "8"
        case 0x1D: return "0"
        case 0x1E: return "]"
        case 0x1F: return "O"
        case 0x20: return "U"
        case 0x21: return "["
        case 0x22: return "I"
        case 0x23: return "P"
        case 0x25: return "L"
        case 0x26: return "J"
        case 0x27: return "'"
        case 0x28: return "K"
        case 0x29: return ";"
        case 0x2A: return "\\"
        case 0x2B: return ","
        case 0x2C: return "/"
        case 0x2D: return "N"
        case 0x2E: return "M"
        case 0x2F: return "."
        case 0x32: return "`"

        default:
            if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
               let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
                let data = unsafeBitCast(ptr, to: CFData.self)
                if let bytes = CFDataGetBytePtr(data) {
                    var deadKeyState: UInt32 = 0
                    var length = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
                        UCKeyTranslate(
                            layout,
                            keyCode,
                            UInt16(kUCKeyActionDown),
                            0,
                            UInt32(LMGetKbdType()),
                            OptionBits(kUCKeyTranslateNoDeadKeysBit),
                            &deadKeyState,
                            chars.count,
                            &length,
                            &chars
                        )
                    }
                    if status == noErr, length > 0 {
                        let str = String(utf16CodeUnits: chars, count: length).uppercased()
                        if !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return str
                        }
                    }
                }
            }
            return "Key(\(keyCode))"
        }
    }
}

// MARK: - Key Shortcut Simulation

/// Posts a key press with its modifiers held, as hardware-like events tagged as MouseFlow's own.
func simulateKeyShortcut(keyCode: CGKeyCode, modifierFlags: CGEventFlags) {
    let modifierKeyCodes: [(CGEventFlags, CGKeyCode)] = [
        (.maskShift, 0x38),
        (.maskControl, 0x3B),
        (.maskAlternate, 0x3A),
        (.maskCommand, 0x37)
    ]
    let activeModifiers = modifierKeyCodes.filter { modifierFlags.contains($0.0) }

    var accumulated = CGEventFlags()
    for (flag, kCode) in activeModifiers {
        accumulated.insert(flag)
        if let event = CGEvent.makeHardwareLikeKeyEvent(virtualKey: kCode, keyDown: true) {
            event.type = .flagsChanged
            event.flags = accumulated
            event.isMouseFlowSyntheticEvent = true
            event.post(tap: .cgSessionEventTap)
        }
    }

    if let keyDown = CGEvent.makeHardwareLikeKeyEvent(virtualKey: keyCode, keyDown: true) {
        keyDown.flags = modifierFlags
        keyDown.isMouseFlowSyntheticEvent = true
        keyDown.post(tap: .cgSessionEventTap)
    }
    if let keyUp = CGEvent.makeHardwareLikeKeyEvent(virtualKey: keyCode, keyDown: false) {
        keyUp.flags = modifierFlags
        keyUp.isMouseFlowSyntheticEvent = true
        keyUp.post(tap: .cgSessionEventTap)
    }

    for (flag, kCode) in activeModifiers.reversed() {
        accumulated.remove(flag)
        if let event = CGEvent.makeHardwareLikeKeyEvent(virtualKey: kCode, keyDown: false) {
            event.type = .flagsChanged
            event.flags = accumulated
            event.isMouseFlowSyntheticEvent = true
            event.post(tap: .cgSessionEventTap)
        }
    }
}
