import AppKit
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: KeyboardShortcutPreference

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let control = ShortcutRecorderControl()
        control.currentShortcut = shortcut
        control.onShortcutChange = { newShortcut in
            shortcut = newShortcut
        }
        return control
    }

    func updateNSView(_ nsView: ShortcutRecorderControl, context: Context) {
        nsView.currentShortcut = shortcut
    }
}

final class ShortcutRecorderControl: NSControl {
    var currentShortcut: KeyboardShortcutPreference = .default {
        didSet {
            needsDisplay = true
        }
    }

    var onShortcutChange: ((KeyboardShortcutPreference) -> Void)?

    private var isRecording = false {
        didSet {
            needsDisplay = true
            if isRecording {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }

    private var eventMonitor: Any?
    private var eventMonitors: [Any] = []

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        // NSView deallocation happens on the main thread
        MainActor.assumeIsolated {
            stopMonitoring()
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 32)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let text = isRecording ? "Press shortcut keys..." : currentShortcut.displayString
        let color: NSColor = isRecording ? .controlAccentColor : .labelColor
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]

        let size = text.size(withAttributes: attrs)
        let rect = NSRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )

        text.draw(in: rect, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        isRecording.toggle()
        if isRecording {
            window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Escape to cancel
        if event.keyCode == 53 {
            isRecording = false
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Ignore pure modifier keys
        if isPureModifier(event.keyCode) {
            return
        }

        // Require at least one modifier
        guard !modifiers.isEmpty else {
            NSSound.beep()
            return
        }

        let newShortcut = KeyboardShortcutPreference(keyCode: event.keyCode, modifiers: modifiers)
        currentShortcut = newShortcut
        onShortcutChange?(newShortcut)
        isRecording = false
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }

        return handleKeyEvent(event)
    }

    override func flagsChanged(with event: NSEvent) {
        // Just ignore modifier-only events
    }

    private func startMonitoring() {
        stopMonitoring()

        // Use BOTH local and global monitors
        // Local monitor catches non-Command shortcuts
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil
            }
            return event
        }

        // Global monitor catches Command shortcuts
        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Store both monitors (we'll need to clean up both)
        eventMonitor = localMonitor
        if let globalMonitor = globalMonitor {
            eventMonitors.append(globalMonitor)
        }
    }

    private func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Escape to cancel
        if event.keyCode == 53 {
            isRecording = false
            return true
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Ignore pure modifier keys
        if isPureModifier(event.keyCode) {
            return false
        }

        // Require at least one modifier
        guard !modifiers.isEmpty else {
            NSSound.beep()
            return false
        }

        let newShortcut = KeyboardShortcutPreference(keyCode: event.keyCode, modifiers: modifiers)
        currentShortcut = newShortcut
        onShortcutChange?(newShortcut)
        isRecording = false
        return true
    }

    private func isPureModifier(_ keyCode: UInt16) -> Bool {
        return [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }
}
