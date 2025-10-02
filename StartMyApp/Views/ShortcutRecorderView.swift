import AppKit
import SwiftUI

struct ShortcutRecorderView: View {
    @Binding var shortcut: KeyboardShortcutPreference

    @State private var isCapturing = false
    @State private var localMonitor: Any?

    var body: some View {
        Button(action: toggleCapture) {
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
                Text(labelText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isCapturing ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Configure shortcut")
        .onChange(of: isCapturing) { _, capturing in
            capturing ? startCapture() : stopCapture()
        }
        .onDisappear(perform: stopCapture)
    }

    private var labelText: String {
        isCapturing ? "按下新的快捷键…" : shortcut.displayString
    }

    private func toggleCapture() {
        isCapturing.toggle()
    }

    private func startCapture() {
        stopCapture()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event: event)
            return nil
        }
    }

    private func stopCapture() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
        isCapturing = false
    }

    private func handle(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == 53 && modifiers.isEmpty { // escape cancels
            stopCapture()
            return
        }

        guard !modifiers.isEmpty else { return }
        guard !isPureModifier(event.keyCode) else { return }

        let updated = shortcut.withUpdated(keyCode: event.keyCode, modifiers: modifiers)
        shortcut = updated
        stopCapture()
    }

    private func isPureModifier(_ keyCode: UInt16) -> Bool {
        return [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }
}
