import AppKit
import SwiftUI

final class LearnWindowController: NSWindowController {
    static let shared = LearnWindowController()

    private var currentApp: DiscoveredApp?

    private init() {
        let view = LearnView(app: nil)
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 600, height: 800))
        window.minSize = NSSize(width: 500, height: 500)
        window.level = .normal
        window.center()
        window.title = "App Info"
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(for app: DiscoveredApp) {
        currentApp = app

        // Update the view with the new app
        let view = LearnView(app: app)
        let controller = NSHostingController(rootView: view)
        window?.contentViewController = controller
        window?.title = "App Info - \(app.name)"

        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
