// GestureEvent.swift

import AppKit
import CoreGraphics

// MARK: - GestureKit Zoom Extensions & GestureEvent

extension CGEventField {
    static let gestureHIDType = CGEventField(rawValue: 110)!
    static let gestureZoomValue = CGEventField(rawValue: 113)!
    static let gesturePhase = CGEventField(rawValue: 132)!
}

enum CGSGesturePhase: UInt8, Sendable {
    case began = 1
    case changed = 2
    case ended = 4
}

private enum IOHIDEventType: UInt32 {
    case zoom = 8
}

enum IOHIDSwipeMask: UInt32 {
    case swipeLeft = 0x04
    case swipeRight = 0x08
}

final class GestureEvent {
    let cgEvents: [CGEvent]

    init(cgEvents: [CGEvent]) {
        self.cgEvents = cgEvents
    }

    func post(tap: CGEventTapLocation = .cgSessionEventTap) {
        for cgEvent in cgEvents {
            cgEvent.post(tap: tap)
        }
    }

    convenience init?(zoomSource: CGEventSource? = nil, phase: CGSGesturePhase, magnification: Double) {
        guard let event = CGEvent(source: zoomSource) else {
            return nil
        }

        event.type = CGEventType(rawValue: UInt32(NSEvent.EventType.gesture.rawValue))!
        event.flags = []
        event.setIntegerValueField(.gestureHIDType, value: Int64(IOHIDEventType.zoom.rawValue))
        event.setIntegerValueField(.gesturePhase, value: Int64(phase.rawValue))
        event.setDoubleValueField(.gestureZoomValue, value: magnification)

        self.init(cgEvents: [event])
    }

    convenience init?(navigationSwipeSource: CGEventSource? = nil, direction: IOHIDSwipeMask) {
        guard let swipeBeganEvent = CGEvent(source: navigationSwipeSource),
              let swipeEndedEvent = CGEvent(source: navigationSwipeSource) else {
            return nil
        }

        guard let gestureEventType = CGEventType(rawValue: 29),
              let gestureHIDType = CGEventField(rawValue: 110),
              let gesturePhase = CGEventField(rawValue: 132),
              let gestureSwipeValue = CGEventField(rawValue: 115) else {
            return nil
        }

        swipeBeganEvent.type = gestureEventType
        swipeBeganEvent.setIntegerValueField(gestureHIDType, value: 16)
        swipeBeganEvent.setIntegerValueField(gesturePhase, value: 1)
        swipeBeganEvent.setIntegerValueField(gestureSwipeValue, value: Int64(direction.rawValue))

        swipeEndedEvent.type = gestureEventType
        swipeEndedEvent.setIntegerValueField(gestureHIDType, value: 16)
        swipeEndedEvent.setIntegerValueField(gesturePhase, value: 4)

        self.init(cgEvents: [swipeBeganEvent, swipeEndedEvent])
    }
}
