// Button macros: a list of key presses, typed text and pauses, recorded in Settings and played back in order.

import CoreGraphics
import Foundation

/// One step of a macro.
enum MacroStep: Codable, Equatable {
    case key(KeyShortcut)
    case text(String)
    case delay(milliseconds: Int)
}

enum Macro {
    static let maxSteps = 200
    static let maxDelay = 10_000

    /// "1 step", "3 steps".
    static func stepCount(_ steps: [MacroStep]) -> String {
        steps.count == 1 ? "1 step" : "\(steps.count) steps"
    }
}

// MARK: - MacroPlayer

/// Plays macros on a background queue, so pauses never block the main thread.
/// A press that arrives while a macro is still playing is ignored.
final class MacroPlayer {
    static let shared = MacroPlayer()

    private let queue = DispatchQueue(label: "MouseFlow.MacroPlayer")
    private let lock = NSLock()
    private var isPlaying = false

    /// Gap after each step, so apps see consecutive key presses as separate presses.
    private static let stepGap: useconds_t = 20_000

    func play(_ steps: [MacroStep]) {
        lock.lock()
        defer { lock.unlock() }
        guard !isPlaying, !steps.isEmpty else { return }
        isPlaying = true

        queue.async { [self] in
            for step in steps {
                perform(step)
                usleep(Self.stepGap)
            }
            lock.lock()
            isPlaying = false
            lock.unlock()
        }
    }

    private func perform(_ step: MacroStep) {
        switch step {
        case let .key(shortcut):
            simulateKeyShortcut(keyCode: shortcut.keyCode, modifierFlags: shortcut.modifierFlags)
        case let .text(text):
            typeText(text)
        case let .delay(milliseconds):
            usleep(useconds_t(min(max(milliseconds, 0), Macro.maxDelay)) * 1000)
        }
    }

    /// Types text as Unicode key events, one character at a time, so it doesn't depend on the keyboard layout.
    private func typeText(_ text: String) {
        for character in text {
            let units = Array(String(character).utf16)
            for keyDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: keyDown) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event.isMouseFlowSyntheticEvent = true
                event.post(tap: .cgSessionEventTap)
            }
            usleep(5_000)
        }
    }
}

// MARK: - MacroRecorder

/// Records key presses as macro steps. Recorded keys are swallowed so they don't reach other apps,
/// and a pause of `minPause` or more between two keys becomes a Wait step.
@MainActor
final class MacroRecorder: ObservableObject {
    @Published private(set) var isRecording = false

    private static let minPause = 250
    private var observationToken: ObservationToken?
    private var lastKeyTime: UInt64?
    private var onStep: ((MacroStep) -> Void)?

    func start(onStep: @escaping (MacroStep) -> Void) {
        guard observationToken == nil else { return }
        self.onStep = onStep
        lastKeyTime = nil

        observationToken = captureKeyPresses { [weak self] shortcut, time in
            self?.record(.key(shortcut), at: time)
        }
        isRecording = observationToken != nil
        if !isRecording {
            NSLog("[MouseFlow] Macro recording couldn't start: no event tap")
        }
    }

    func stop() {
        observationToken?.cancel()
        observationToken = nil
        onStep = nil
        isRecording = false
    }

    private func record(_ step: MacroStep, at time: UInt64) {
        guard isRecording else { return }
        if let lastKeyTime {
            let pause = Int((time - lastKeyTime) / 1_000_000)
            if pause >= Self.minPause {
                // Rounded to 50 ms so recorded pauses read cleanly.
                onStep?(.delay(milliseconds: min(pause / 50 * 50, Macro.maxDelay)))
            }
        }
        lastKeyTime = time
        onStep?(step)
    }
}
