// EventTap.swift

import CoreGraphics
import Foundation

// MARK: - ObservationToken

/// Lifetime-scoped cancellation handle for an event tap observation.
final class ObservationToken {
    private let cancellationClosure: () -> Void
    private var cancelled = false

    init(cancellationClosure: @escaping () -> Void) {
        self.cancellationClosure = cancellationClosure
    }

    deinit { cancel() }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        cancellationClosure()
    }
}

// MARK: - EventTap

/// EventTap wrapper managing CGEvent.tapCreate and RunLoop lifecycle.
enum EventTapError: Error {
    case failedToCreate
}

enum EventTap {
    typealias Callback = (_ proxy: CGEventTapProxy, _ event: CGEvent) -> CGEvent?

    private class ContextHolder {
        var tap: CFMachPort?
        let callback: Callback
        init(_ callback: @escaping Callback) { self.callback = callback }
    }

    private static let callbackInvoker: CGEventTapCallBack = { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
        guard let refcon else { return Unmanaged.passUnretained(event) }

        let contextHolder = Unmanaged<ContextHolder>.fromOpaque(refcon).takeUnretainedValue()
        let tap = contextHolder.tap
        let callback = contextHolder.callback

        switch type {
        case .tapDisabledByUserInput:
            return Unmanaged.passUnretained(event)
        case .tapDisabledByTimeout:
            NSLog("[MouseFlow] EventTap disabled by timeout, re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        default:
            let originalEvent = event
            guard let event = callback(proxy, event) else { return nil }
            return event === originalEvent ? Unmanaged.passUnretained(event) : Unmanaged.passRetained(event)
        }
    }

    static func observe(
        _ events: [CGEventType],
        onInvalidated: (() -> Void)? = nil,
        callback: @escaping Callback
    ) throws -> ObservationToken {
        let contextHolder = ContextHolder(callback)
        let eventsOfInterest = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: callbackInvoker,
            userInfo: Unmanaged.passUnretained(contextHolder).toOpaque()
        ) else {
            throw EventTapError.failedToCreate
        }

        contextHolder.tap = tap

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let runLoop = RunLoop.current
        let cfRunLoop = runLoop.getCFRunLoop()
        CFRunLoopAddSource(cfRunLoop, runLoopSource, .commonModes)

        var didNotifyInvalidation = false
        let healthCheckTimer = Timer(timeInterval: 5, repeats: true) { _ in
            guard CFMachPortIsValid(tap) else {
                guard !didNotifyInvalidation else { return }
                didNotifyInvalidation = true
                NSLog("[MouseFlow] EventTap became invalid")
                onInvalidated?()
                return
            }
            if !CGEvent.tapIsEnabled(tap: tap) {
                NSLog("[MouseFlow] EventTap found disabled, re-enabling")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        runLoop.add(healthCheckTimer, forMode: .common)

        return ObservationToken {
            CFRunLoopPerformBlock(cfRunLoop, CFRunLoopMode.commonModes.rawValue) {
                healthCheckTimer.invalidate()
                CGEvent.tapEnable(tap: tap, enable: false)
                CFRunLoopRemoveSource(cfRunLoop, runLoopSource, .commonModes)
                CFMachPortInvalidate(tap)
                withExtendedLifetime(contextHolder) {}
            }
            CFRunLoopWakeUp(cfRunLoop)
        }
    }
}

// MARK: - EventThread

/// Dedicated background thread with its own RunLoop for low-latency event processing.
final class EventThread {
    static let shared = EventThread()

    private(set) var runLoop: RunLoop?
    private var thread: Thread?
    private let runLoopReady = DispatchSemaphore(value: 0)

    var isCurrent: Bool { Thread.current === thread }

    func start() {
        guard thread == nil else { return }
        let thread = Thread { [weak self] in
            guard let self else { return }
            let rl = RunLoop.current
            rl.add(Port(), forMode: .common)
            self.runLoop = rl
            self.runLoopReady.signal()
            CFRunLoopRun()
        }
        thread.name = "\(Bundle.main.bundleIdentifier!).event-thread"
        thread.qualityOfService = QualityOfService.userInteractive
        self.thread = thread
        thread.start()
        runLoopReady.wait()
    }

    func stop() {
        precondition(!isCurrent, "EventThread.stop() must not be called from the event thread")
        guard let cfRunLoop = runLoop?.getCFRunLoop() else { return }
        let done = DispatchSemaphore(value: 0)
        CFRunLoopPerformBlock(cfRunLoop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
            self?.thread?.cancel()
            self?.thread = nil
            self?.runLoop = nil
        }
        CFRunLoopPerformBlock(cfRunLoop, CFRunLoopMode.commonModes.rawValue) {
            CFRunLoopStop(cfRunLoop)
            done.signal()
        }
        CFRunLoopWakeUp(cfRunLoop)
        done.wait()
    }

    func performAndWait<T>(_ block: @escaping () -> T) -> T? {
        if isCurrent { return block() }
        guard let cfRunLoop = runLoop?.getCFRunLoop() else { return nil }
        let done = DispatchSemaphore(value: 0)
        var result: T?
        CFRunLoopPerformBlock(cfRunLoop, CFRunLoopMode.commonModes.rawValue) {
            result = block()
            done.signal()
        }
        CFRunLoopWakeUp(cfRunLoop)
        done.wait()
        return result
    }
}

// MARK: - CGEvent Extensions

extension CGEvent {
    static let syntheticEventUserData: Int64 = 0x534D_4F4F_5448

    var isMouseFlowSyntheticEvent: Bool {
        get {
            getIntegerValueField(.eventSourceUserData) == Self.syntheticEventUserData
        }
        set {
            setIntegerValueField(
                .eventSourceUserData,
                value: newValue ? Self.syntheticEventUserData : 0
            )
        }
    }
}
