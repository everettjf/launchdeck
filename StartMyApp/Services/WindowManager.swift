import AppKit

final class WindowManager {
    static let shared = WindowManager()

    private init() {}

    func showMainWindow() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            // Debug: Print all windows
            print("All windows:")
            for window in NSApp.windows {
                print("  - \(window.className), title: '\(window.title)', canBecomeKey: \(window.canBecomeKey), level: \(window.level.rawValue)")
            }

            // Find the main app window (WindowGroup window)
            let mainWindow = NSApp.windows.first { window in
                // Look for SwiftUI WindowGroup window
                let isSwiftUIWindow = window.className.contains("SwiftUI")
                let canBeKey = window.canBecomeKey
                let isNormalLevel = window.level == .normal
                let notStatusBar = !window.className.contains("StatusBar")
                let notSettings = !window.title.contains("Settings") && !window.title.contains("Preferences")

                print("Checking window: \(window.className)")
                print("  isSwiftUIWindow: \(isSwiftUIWindow), canBeKey: \(canBeKey), isNormalLevel: \(isNormalLevel), notStatusBar: \(notStatusBar), notSettings: \(notSettings)")

                return canBeKey && isNormalLevel && notStatusBar && notSettings
            }

            guard let window = mainWindow else {
                print("No suitable main window found")
                return
            }

            print("Found main window: \(window.className)")
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }
}
