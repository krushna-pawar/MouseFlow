// ScrollPipeline.swift
// The scroll path for wheel events from a mouse.

import CoreGraphics
import Foundation

/// Decides what happens to a scroll-wheel event from a mouse, using one config snapshot:
/// a held Zoom key turns it into a pinch-zoom gesture; otherwise it is reversed, turned sideways
/// by the Horizontal key, then either handed to smooth scrolling or set to fixed lines per tick.
/// The tap only sends events from devices of category `.mouse`.
final class ScrollPipeline {
    private let pinchZoom = PinchZoomHandler()

    /// Rewrites `event` in place and returns it, or returns nil when the event is consumed
    /// (turned into a zoom gesture, handed to smooth scrolling, or a dropped momentum event).
    func process(_ event: CGEvent, config: TapConfig) -> CGEvent? {
        let held = ScrollModifiers.activeFeatures(config.scrollModifierConfigs, flags: event.flags)
        if held.contains(.zoom) {
            pinchZoom.scroll(event)
            return nil
        }
        let multiplier = held.contains(.fast) ? ScrollModifiers.fastMultiplier : 1.0
        let view = ScrollWheelEventView(event)

        if config.windowsStyleScrolling {
            view.negateVertical()
        }
        // Horizontal modifier: turn the vertical wheel into sideways scrolling.
        if held.contains(.horizontal), view.deltaYSignum != 0 {
            view.swapAxes()
        }

        if config.smoothScrolling {
            SmoothScrollEngine.shared.postScroll(from: event, config: config, multiplier: multiplier)
            return nil
        }

        // Horizontal speed (and fast scroll) for sideways scrolling, from a tilt wheel or the modifier.
        let horizontalFactor = config.horizontalScrollSpeed * multiplier
        if view.deltaXSignum != 0, view.deltaYSignum == 0, horizontalFactor != 1.0 {
            view.scaleX(by: horizontalFactor)
        }

        return Self.applyLinesPerTick(view, lines: config.scrollLines * multiplier)
    }

    /// Ends an ongoing pinch zoom once the Zoom key is no longer held.
    func modifiersChanged(_ held: Set<ScrollModifierFeature>) {
        pinchZoom.zoomKeyChanged(isHeld: held.contains(.zoom))
    }

    /// Stops any smooth-scrolling glide in progress.
    func reset() {
        SmoothScrollEngine.shared.reset()
    }

    /// Fixed lines per wheel notch.
    /// Vertical events become discrete steps of `lines` lines; their momentum events are dropped.
    private static func applyLinesPerTick(_ view: ScrollWheelEventView, lines: Double) -> CGEvent? {
        guard view.deltaYSignum != 0 else { return view.event }
        guard view.momentumPhase == .none else { return nil }
        view.continuous = false
        view.deltaY = view.deltaYSignum * Int64(max(1, Int(lines.rounded())))
        view.deltaX = 0
        return view.event
    }
}

// MARK: - PinchZoomHandler

/// Turns scrolling with the Zoom key held into a trackpad-style pinch-zoom gesture.
/// The gesture ends when the key is released or 0.3 s after the last scroll.
private final class PinchZoomHandler {
    private var pinchZoomBegan = false
    private var pinchZoomEndTimer: DispatchSourceTimer?
    private let lock = NSLock()

    func scroll(_ event: CGEvent) {
        lock.lock()
        defer { lock.unlock() }

        if !pinchZoomBegan {
            GestureEvent(phase: .began, magnification: 0)?.post(tap: .cgSessionEventTap)
            pinchZoomBegan = true
        }

        let view = ScrollWheelEventView(event)
        let deltaY = view.deltaYPt != 0
            ? view.deltaYPt
            : Double(view.deltaYSignum != 0 ? view.deltaYSignum : view.deltaY) * 10.0
        GestureEvent(phase: .changed, magnification: deltaY * 0.005)?.post(tap: .cgSessionEventTap)

        schedulePinchZoomEnd()
    }

    func zoomKeyChanged(isHeld: Bool) {
        lock.lock()
        defer { lock.unlock() }

        if pinchZoomBegan && !isHeld {
            endPinchZoom()
        }
    }

    /// Call with `lock` held.
    private func endPinchZoom() {
        pinchZoomEndTimer?.cancel()
        pinchZoomEndTimer = nil
        if pinchZoomBegan {
            pinchZoomBegan = false
            GestureEvent(phase: .ended, magnification: 0)?.post(tap: .cgSessionEventTap)
        }
    }

    private func schedulePinchZoomEnd() {
        pinchZoomEndTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.3)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            self.endPinchZoom()
        }
        timer.resume()
        pinchZoomEndTimer = timer
    }
}
