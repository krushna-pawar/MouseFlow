import SwiftUI

/// Lets Settings present the macro editor with `.sheet(item:)`.
extension MouseButton: Identifiable {
    var id: Self { self }
}

/// Sheet for a button's macro: record key presses, add text and pauses, reorder and delete steps.
/// Changes apply only on Save.
struct MacroEditor: View {
    let buttonLabel: String
    let onSave: ([MacroStep]) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = MacroRecorder()
    @State private var items: [Item]

    /// A step with a stable identity, so rows keep their edits while the list changes.
    private struct Item: Identifiable {
        let id = UUID()
        var step: MacroStep
    }

    init(buttonLabel: String, steps: [MacroStep], onSave: @escaping ([MacroStep]) -> Void) {
        self.buttonLabel = buttonLabel
        self.onSave = onSave
        _items = State(initialValue: steps.map { Item(step: $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Macro for \(buttonLabel)")
                    .font(.headline)
                Text("Click Record and press keys. Pauses of a quarter second or longer become Wait steps. Keys you press while recording don't reach other apps. Click Stop when you're done.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            List {
                ForEach($items) { $item in
                    stepRow($item)
                }
                .onMove { items.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(minHeight: 240)
            .overlay {
                if items.isEmpty {
                    Text(recorder.isRecording ? "Press keys…" : "No steps yet")
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Button {
                    toggleRecording()
                } label: {
                    Label(recorder.isRecording ? "Stop" : "Record", systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                }
                Button("Add Text") { append(.text("")) }
                    .disabled(recorder.isRecording)
                Button("Add Wait") { append(.delay(milliseconds: 100)) }
                    .disabled(recorder.isRecording)
                Spacer()
                Button("Clear All") { items.removeAll() }
                    .disabled(items.isEmpty || recorder.isRecording)
            }

            HStack {
                Text(Macro.stepCount(items.map(\.step)))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(items.map(\.step).filter { $0 != .text("") })
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onDisappear { recorder.stop() }
    }

    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stop()
        } else {
            recorder.start { step in
                append(step)
                if items.count >= Macro.maxSteps {
                    recorder.stop()
                }
            }
        }
    }

    private func append(_ step: MacroStep) {
        guard items.count < Macro.maxSteps else { return }
        items.append(Item(step: step))
    }

    private func stepRow(_ item: Binding<Item>) -> some View {
        HStack(spacing: 8) {
            switch item.wrappedValue.step {
            case let .key(shortcut):
                Image(systemName: "keyboard")
                    .frame(width: 18)
                Text(shortcut.displayString)
                    .fontWeight(.medium)
            case let .text(text):
                Image(systemName: "textformat")
                    .frame(width: 18)
                TextField("Text to type", text: Binding(
                    get: { text },
                    set: { item.wrappedValue.step = .text($0) }
                ))
                .disabled(recorder.isRecording)
            case let .delay(milliseconds):
                Image(systemName: "timer")
                    .frame(width: 18)
                Text("Wait")
                TextField("ms", value: Binding(
                    get: { milliseconds },
                    set: { item.wrappedValue.step = .delay(milliseconds: min(max($0, 0), Macro.maxDelay)) }
                ), format: .number)
                .frame(width: 70)
                .disabled(recorder.isRecording)
                Text("ms")
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                items.removeAll { $0.id == item.wrappedValue.id }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove step")
            .disabled(recorder.isRecording)
        }
        .padding(.vertical, 2)
    }
}
