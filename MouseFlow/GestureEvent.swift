import AppKit
import CoreGraphics

// MARK: - Zoom & Swipe Gesture Events

extension CGEventField {
    static let gestureHIDType = CGEventField(rawValue: 110)!
    static let gestureZoomValue = CGEventField(rawValue: 113)!
    static let gestureSwipeValue = CGEventField(rawValue: 115)!
    static let gesturePhase = CGEventField(rawValue: 132)!
}

enum CGSGesturePhase: UInt8, Sendable {
    case began = 1
    case changed = 2
    case ended = 4
}

private enum IOHIDEventType: UInt32 {
    case zoom = 8
    case swipe = 16
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

    convenience init?(phase: CGSGesturePhase, magnification: Double) {
        guard let event = CGEvent(source: nil) else {
            return nil
        }

        event.type = CGEventType(rawValue: UInt32(NSEvent.EventType.gesture.rawValue))!
        event.flags = []
        event.setIntegerValueField(.gestureHIDType, value: Int64(IOHIDEventType.zoom.rawValue))
        event.setIntegerValueField(.gesturePhase, value: Int64(phase.rawValue))
        event.setDoubleValueField(.gestureZoomValue, value: magnification)

        self.init(cgEvents: [event])
    }

    convenience init?(direction: IOHIDSwipeMask) {
        guard let swipeBeganEvent = CGEvent(source: nil),
              let swipeEndedEvent = CGEvent(source: nil) else {
            return nil
        }

        let gestureEventType = CGEventType(rawValue: UInt32(NSEvent.EventType.gesture.rawValue))!

        swipeBeganEvent.type = gestureEventType
        swipeBeganEvent.setIntegerValueField(.gestureHIDType, value: Int64(IOHIDEventType.swipe.rawValue))
        swipeBeganEvent.setIntegerValueField(.gesturePhase, value: Int64(CGSGesturePhase.began.rawValue))
        swipeBeganEvent.setIntegerValueField(.gestureSwipeValue, value: Int64(direction.rawValue))

        swipeEndedEvent.type = gestureEventType
        swipeEndedEvent.setIntegerValueField(.gestureHIDType, value: Int64(IOHIDEventType.swipe.rawValue))
        swipeEndedEvent.setIntegerValueField(.gesturePhase, value: Int64(CGSGesturePhase.ended.rawValue))

        self.init(cgEvents: [swipeBeganEvent, swipeEndedEvent])
    }
}
