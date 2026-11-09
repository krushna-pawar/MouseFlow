import CoreGraphics
import CoreVideo
import Foundation
import os

// MARK: - Interpolator & ScrollFilter

enum Interpolator {
    static func lerp(src: Double, dest: Double, trans: Double) -> Double {
        let x = dest - src
        return x * trans
    }
}

final class ScrollFilter {
    private var curveWindowY: [Double] = [0.0, 0.0]
    private var curveWindowX: [Double] = [0.0, 0.0]

    func fill(with nextValue: (y: Double, x: Double)) -> (y: Double, x: Double) {
        curveWindowY = polish(curveWindowY, with: nextValue.y)
        curveWindowX = polish(curveWindowX, with: nextValue.x)
        return (y: curveWindowY[0], x: curveWindowX[0])
    }

    func reset() {
        curveWindowY = [0.0, 0.0]
        curveWindowX = [0.0, 0.0]
    }

    private func polish(_ array: [Double], with nextValue: Double) -> [Double] {
        let first = array[1]
        let diff = nextValue - first
        return [first, first + 0.23 * diff, first + 0.5 * diff, first + 0.77 * diff, nextValue]
    }
}

// MARK: - SmoothScrollEngine
// - Normalizes discrete mouse wheel input to stable per-notch distances
// - Accumulates motion into buffer with direction-reversal reset
// - Clamps maximum lead buffer to prevent runaway backlog on longer scrolls
// - Drives frame interpolation via CVDisplayLink using lerp + ScrollFilter
// - Emits continuous synthetic frames with the synthetic event marker
// - Decays to rest and automatically stops CVDisplayLink when idle

final class SmoothScrollEngine {
    static let shared = SmoothScrollEngine()

    private let filter = ScrollFilter()
    private var displayLink: CVDisplayLink?
    private var isRunning: Bool = false
    private var stateLock = os_unfair_lock_s()

    private var buffer = (y: 0.0, x: 0.0)
    private var current = (y: 0.0, x: 0.0)
    private var delta = (y: 0.0, x: 0.0)

    // Initial value only; ScrollSmoothness.duration replaces it on each scroll. Larger values settle faster.
    private var baseDuration: Double = 0.16
    private let deadZone: Double = 1.0

    private var eventTemplate: CGEvent?
    private var lastFrameTime: CFTimeInterval = 0.0
    private var lastInputTime: CFTimeInterval = 0.0
    private var stopScheduled: Bool = false

    init() {
        var link: CVDisplayLink?
        let status = CVDisplayLinkCreateWithActiveCGDisplays(&link)
        if status == kCVReturnSuccess, let validLink = link {
            let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, _ in
                SmoothScrollEngine.shared.processing()
                return kCVReturnSuccess
            }
            CVDisplayLinkSetOutputCallback(validLink, callback, nil)
            self.displayLink = validLink
        } else {
            NSLog("[MouseFlow] SmoothScrollEngine: Failed to create CVDisplayLink (%d)", status)
        }
    }

    /// The discrete delta when there is one, else one notch in the direction of the pixel delta.
    private static func notchCount(discrete: Int64, point: Double) -> Double {
        if discrete != 0 { return Double(discrete) }
        if abs(point) > 0.001 { return point > 0 ? 1.0 : -1.0 }
        return 0.0
    }

    /// Captures a discrete mouse wheel event and feeds its effective delta into the accumulator.
    /// `multiplier` is the fast scroll factor for this event.
    func postScroll(from event: CGEvent, config: TapConfig, multiplier: Double = 1.0) {
        guard let copy = event.copy() else { return }

        let view = ScrollWheelEventView(event)

        // Extract discrete notch count (un-accelerated to prevent exponential velocity buildup on longer scrolls)
        let notchY = Self.notchCount(discrete: view.deltaY, point: view.deltaYPt)
        let notchX = Self.notchCount(discrete: view.deltaX, point: view.deltaXPt)

        guard notchY != 0.0 || notchX != 0.0 else { return }

        // Baseline step: lines * 11.2 pt. Default 3 lines = 33.6 pt.
        let lines = max(1.0, config.scrollLines)
        let speed = max(0.1, config.scrollSpeed) * multiplier
        let horizontalSpeed = max(0.1, config.horizontalScrollSpeed)
        let duration = config.smoothness.duration
        let step = lines * 11.2

        let scrollDeltaY = notchY * step * speed
        let scrollDeltaX = notchX * step * speed * horizontalSpeed

        os_unfair_lock_lock(&stateLock)
        baseDuration = duration
        eventTemplate = copy
        lastInputTime = CFAbsoluteTimeGetCurrent()

        // Direction-reversal & accumulation behavior:
        if scrollDeltaY * delta.y > 0 {
            buffer.y += scrollDeltaY
        } else {
            buffer.y = scrollDeltaY
            current.y = 0.0
            filter.reset()
        }

        if scrollDeltaX * delta.x > 0 {
            buffer.x += scrollDeltaX
        } else {
            buffer.x = scrollDeltaX
            current.x = 0.0
        }
        delta = (y: scrollDeltaY, x: scrollDeltaX)

        // Lead cap: clamp the leading buffer distance to at most 6 notches ahead of current position.
        // A long or fast spin can't pile up a backlog, so motion settles within ~150-200 ms after the wheel stops.
        let maxLead = step * 6.0 * max(1.0, multiplier)
        buffer.y = min(max(buffer.y, current.y - maxLead), current.y + maxLead)
        buffer.x = min(max(buffer.x, current.x - maxLead), current.x + maxLead)

        stopScheduled = false
        startDisplayLinkLocked()
        os_unfair_lock_unlock(&stateLock)
    }

    private func startDisplayLinkLocked() {
        guard let displayLink else { return }
        if !isRunning {
            let status = CVDisplayLinkStart(displayLink)
            if status == kCVReturnSuccess {
                isRunning = true
                lastFrameTime = CFAbsoluteTimeGetCurrent()
            }
        }
    }

    /// Display-refresh callback.
    func processing() {
        os_unfair_lock_lock(&stateLock)
        let now = CFAbsoluteTimeGetCurrent()
        let dt = lastFrameTime > 0 ? max(0.001, min(0.05, now - lastFrameTime)) : 0.016
        lastFrameTime = now

        // Frame-rate normalized transition factor (normalized to 60Hz)
        let frameRatio = dt / (1.0 / 60.0)
        let trans = min(0.4, 1.0 - pow(1.0 - baseDuration, frameRatio))

        // Interpolation: lerp toward buffer
        let frame = (
            y: Interpolator.lerp(src: current.y, dest: buffer.y, trans: trans),
            x: Interpolator.lerp(src: current.x, dest: buffer.x, trans: trans)
        )
        current = (
            y: current.y + frame.y,
            x: current.x + frame.x
        )

        // Jitter filter: polish curveWindow to smooth jitter
        let filledValue = filter.fill(with: frame)

        // Convergence & dead zone check
        let residualY = buffer.y - current.y
        let residualX = buffer.x - current.x
        let residualMagnitude = max(abs(residualY), abs(residualX))
        let outputMagnitude = max(abs(filledValue.y), abs(filledValue.x))

        let isSettled = residualMagnitude <= deadZone && outputMagnitude <= deadZone
        let inputInactive = (now - lastInputTime) > 0.12

        if isSettled && inputInactive {
            current = (y: 0.0, x: 0.0)
            delta = (y: 0.0, x: 0.0)
            buffer = (y: 0.0, x: 0.0)
            filter.reset()
            lastFrameTime = 0.0

            if !stopScheduled {
                stopScheduled = true
                DispatchQueue.main.async { [weak self] in
                    self?.stopDisplayLink()
                }
            }
            os_unfair_lock_unlock(&stateLock)
            return
        }

        guard outputMagnitude > (deadZone * 0.1), let template = eventTemplate?.copy() else {
            os_unfair_lock_unlock(&stateLock)
            return
        }
        os_unfair_lock_unlock(&stateLock)

        // Post synthetic smooth frame
        template.isMouseFlowSyntheticEvent = true

        let view = ScrollWheelEventView(template)
        view.continuous = true
        view.deltaY = 0
        view.deltaX = 0
        view.deltaYPt = filledValue.y
        view.deltaXPt = filledValue.x

        if let loc = CGEvent(source: nil)?.location {
            template.location = loc
        }

        template.post(tap: .cgSessionEventTap)
    }

    private func stopDisplayLink() {
        guard let displayLink else { return }
        os_unfair_lock_lock(&stateLock)
        let residualMagnitude = max(abs(buffer.y - current.y), abs(buffer.x - current.x))
        if isRunning && residualMagnitude <= deadZone {
            CVDisplayLinkStop(displayLink)
            isRunning = false
            stopScheduled = false
        }
        os_unfair_lock_unlock(&stateLock)
    }

    func reset() {
        os_unfair_lock_lock(&stateLock)
        current = (y: 0.0, x: 0.0)
        delta = (y: 0.0, x: 0.0)
        buffer = (y: 0.0, x: 0.0)
        filter.reset()
        lastFrameTime = 0.0
        eventTemplate = nil
        stopScheduled = false
        if isRunning, let displayLink {
            CVDisplayLinkStop(displayLink)
            isRunning = false
        }
        os_unfair_lock_unlock(&stateLock)
    }
}

/// How long smooth scrolling keeps gliding after the wheel stops.
enum ScrollSmoothness: String, CaseIterable {
    case short = "Short"
    case medium = "Medium"
    case long = "Long"

    /// Per-frame interpolation factor at 60 Hz; larger settles faster.
    var duration: Double {
        switch self {
        case .short: return 0.25
        case .medium: return 0.16
        case .long: return 0.0854
        }
    }
}
