import AppKit

final class WindowManager {
    static let shared = WindowManager()

    private init() {}

    func showMainWindow() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.isMiniaturized == false }) ?? NSApp.windows.first else {
                return
            }
            window.makeKeyAndOrderFront(nil)
        }
    }
}
