// ScrollWheelEventView.swift

import CoreGraphics
import Foundation
import simd

// MARK: - ScrollWheelEventView

/// Provides typed accessors and simultaneous transformation operations for all scroll representations.
final class ScrollWheelEventView {
    let event: CGEvent
    private let ioHidEvent: AnyObject?

    init(_ event: CGEvent) {
        assert(event.type == .scrollWheel)
        self.event = event
        if let unmanaged = CGEventCopyIOHIDEvent(event) {
            self.ioHidEvent = unmanaged.takeRetainedValue()
        } else {
            self.ioHidEvent = nil
        }
    }

    var continuous: Bool {
        get { event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 }
        set { event.setIntegerValueField(.scrollWheelEventIsContinuous, value: newValue ? 1 : 0) }
    }

    var momentumPhase: CGMomentumScrollPhase {
        get {
            .init(rawValue: UInt32(event.getIntegerValueField(.scrollWheelEventMomentumPhase))) ?? .none
        }
        set {
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(newValue.rawValue))
        }
    }

    // Vertical (Axis 1)
    var deltaY: Int64 {
        get { event.getIntegerValueField(.scrollWheelEventDeltaAxis1) }
        set { event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: newValue) }
    }

    var deltaYFixedPt: Double {
        get { event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) }
        set { event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: newValue) }
    }

    var deltaYPt: Double {
        get { event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) }
        set { event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: newValue) }
    }

    var deltaYSignum: Int64 {
        continuous ? Int64(deltaYPt > 0 ? 1 : (deltaYPt < 0 ? -1 : 0)) : deltaY.signum()
    }

    // Horizontal (Axis 2)
    var deltaX: Int64 {
        get { event.getIntegerValueField(.scrollWheelEventDeltaAxis2) }
        set { event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: newValue) }
    }

    var deltaXFixedPt: Double {
        get { event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) }
        set { event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: newValue) }
    }

    var deltaXPt: Double {
        get { event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2) }
        set { event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: newValue) }
    }

    var deltaXSignum: Int64 {
        continuous ? Int64(deltaXPt > 0 ? 1 : (deltaXPt < 0 ? -1 : 0)) : deltaX.signum()
    }

    var ioHidScrollX: Double {
        get {
            guard let ioHidEvent else { return 0 }
            return IOHIDEventGetFloatValue(ioHidEvent, kIOHIDEventFieldScrollX)
        }
        set {
            guard let ioHidEvent else { return }
            IOHIDEventSetFloatValue(ioHidEvent, kIOHIDEventFieldScrollX, newValue)
        }
    }

    var ioHidScrollY: Double {
        get {
            guard let ioHidEvent else { return 0 }
            return IOHIDEventGetFloatValue(ioHidEvent, kIOHIDEventFieldScrollY)
        }
        set {
            guard let ioHidEvent else { return }
            IOHIDEventSetFloatValue(ioHidEvent, kIOHIDEventFieldScrollY, newValue)
        }
    }

    /// Full representation matrix: [X; Y] x [discrete, fixedPt, pt, ioHid]
    var matrixValue: simd_double2x4 {
        simd_double2x4(
            [Double(deltaX), deltaXFixedPt, deltaXPt, ioHidScrollX],
            [Double(deltaY), deltaYFixedPt, deltaYPt, ioHidScrollY]
        )
    }

    /// Simultaneous linear transformation of all scroll representations.
    func transform(matrix: simd_double2x2) {
        let oldValue = matrixValue
        let newValue = oldValue * matrix
        let deltaXY = newValue.transpose[0]
        let normalizedDeltaXY = sign(deltaXY) * max(simd.round(abs(deltaXY)), simd_double2(1, 1))
        (deltaX, deltaXFixedPt, deltaXPt, ioHidScrollX) = (
            Int64(normalizedDeltaXY.x),
            newValue[0][1],
            newValue[0][2],
            newValue[0][3]
        )
        (deltaY, deltaYFixedPt, deltaYPt, ioHidScrollY) = (
            Int64(normalizedDeltaXY.y),
            newValue[1][1],
            newValue[1][2],
            newValue[1][3]
        )
    }

    /// Negate the vertical delta.
    func negateVertical() {
        transform(matrix: .init([1, 0], [0, -1]))
    }

    /// Swap the vertical and horizontal deltas (vertical wheel → sideways scrolling).
    func swapAxes() {
        transform(matrix: .init([0, 1], [1, 0]))
    }

    /// Scale the horizontal delta by factor.
    func scaleX(by factor: Double) {
        transform(matrix: .init([factor, 0], [0, 1]))
    }
}
