// EventTap.swift

import CoreGraphics
import Foundation
import os.log

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
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "EventTap")

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
            os_log("EventTap disabled by timeout, re-enabling", log: log, type: .error)
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
        place: CGEventTapPlacement = .headInsertEventTap,
        at runLoop: RunLoop = .current,
        onInvalidated: (() -> Void)? = nil,
        callback: @escaping Callback
    ) throws -> ObservationToken {
        let contextHolder = ContextHolder(callback)
        let eventsOfInterest = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: place,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: callbackInvoker,
            userInfo: Unmanaged.passUnretained(contextHolder).toOpaque()
        ) else {
            os_log("Failed to create event tap", log: log, type: .error)
            throw EventTapError.failedToCreate
        }

        contextHolder.tap = tap

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let cfRunLoop = runLoop.getCFRunLoop()
        CFRunLoopAddSource(cfRunLoop, runLoopSource, .commonModes)

        var didNotifyInvalidation = false
        let healthCheckTimer = Timer(timeInterval: 5, repeats: true) { _ in
            guard CFMachPortIsValid(tap) else {
                guard !didNotifyInvalidation else { return }
                didNotifyInvalidation = true
                os_log("EventTap became invalid", log: log, type: .error)
                onInvalidated?()
                return
            }
            if !CGEvent.tapIsEnabled(tap: tap) {
                os_log("EventTap found disabled, re-enabling", log: log, type: .error)
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

    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "EventThread")

    private(set) var runLoop: RunLoop?
    private var thread: Thread?
    private let runLoopReady = DispatchSemaphore(value: 0)

    init() {}

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
        thread.name = "com.krushna.MouseFlow.event-thread"
        thread.qualityOfService = QualityOfService.userInteractive
        self.thread = thread
        thread.start()
        runLoopReady.wait()
        os_log("EventThread started", log: Self.log, type: .info)
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
        os_log("EventThread stopped", log: Self.log, type: .info)
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
