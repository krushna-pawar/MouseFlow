import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Row 1: MouseFlow [switch]
            Toggle(isOn: $appState.isEnabled) {
                HStack {
                    Text("MouseFlow")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                }
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .padding(.bottom, 1)

            Divider()
                .opacity(0.35)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)

            // Row 2: Sensitivity
            Button(action: { SettingsWindowController.shared.showWindow(tab: .pointer) }) {
                HStack {
                    Text("Sensitivity")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.primary)

                    Spacer()

                    Text(String(format: "%.2f×", appState.pointerSensitivity))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PopoverRowButtonStyle())

            Divider()
                .opacity(0.35)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)

            // Row 3 & 4: Actions
            VStack(alignment: .leading, spacing: 1) {
                Button(action: openSettings) {
                    HStack {
                        Text("Settings…")
                            .font(.system(size: 12))
                            .foregroundColor(.primary.opacity(0.9))
                        Spacer()
                        Text("⌘,")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .buttonStyle(PopoverRowButtonStyle())
                .keyboardShortcut(",", modifiers: .command)

                Button(action: { NSApp.terminate(nil) }) {
                    HStack {
                        Text("Quit MouseFlow")
                            .font(.system(size: 12))
                            .foregroundColor(.primary.opacity(0.9))
                        Spacer()
                        Text("⌘Q")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .buttonStyle(PopoverRowButtonStyle())
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.bottom, 3)
        }
        .padding(6)
        .frame(width: 215)
    }

    private func openSettings() {
        SettingsWindowController.shared.showWindow()
    }
}

private struct PopoverRowButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(configuration.isPressed
                          ? Color.primary.opacity(0.12)
                          : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}
