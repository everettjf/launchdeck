import AppKit
import SwiftUI

/// Bridges the main scene's NSWindow to WindowManager so the window can be
/// found reliably without title/class-name heuristics.
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowAccessorView {
        WindowAccessorView()
    }

    func updateNSView(_ nsView: WindowAccessorView, context: Context) {}

    final class WindowAccessorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                WindowManager.shared.register(window: window)
            }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil, let window {
                WindowManager.shared.unregister(window: window)
            }
        }
    }
}
