import AppKit
import SwiftUI

struct ModifierKeyObserver: NSViewRepresentable {
    @Binding var isCommandPressed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isCommandPressed: $isCommandPressed)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.startMonitoring()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isCommandPressed = $isCommandPressed
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    final class Coordinator {
        var isCommandPressed: Binding<Bool>
        private var monitor: Any?

        init(isCommandPressed: Binding<Bool>) {
            self.isCommandPressed = isCommandPressed
        }

        func startMonitoring() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.isCommandPressed.wrappedValue = event.modifierFlags.contains(.command)
                return event
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            isCommandPressed.wrappedValue = false
        }
    }
}
