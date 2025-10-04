import AppKit

final class WindowManager {
    static let shared = WindowManager()

    private init() {}

    func showMainWindow() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            // Find the main app window (WindowGroup window)
            let mainWindow = NSApp.windows.first { window in
                let canBeKey = window.canBecomeKey
                let isNormalLevel = window.level == .normal
                let notStatusBar = !window.className.contains("StatusBar")
                let notSettings = !window.title.contains("Settings") && !window.title.contains("Preferences")

                return canBeKey && isNormalLevel && notStatusBar && notSettings
            }

            if let window = mainWindow {
                // Window exists, show it
                print("Found existing main window: \(window.className)")
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            } else {
                // No window found, try to create a new one using Cmd+N
                print("No main window found, attempting to create new window")

                // Try to trigger new window via menu
                if let newMenuItem = NSApp.mainMenu?.item(withTitle: "File")?.submenu?.item(withTitle: "New") {
                    NSApp.sendAction(newMenuItem.action!, to: newMenuItem.target, from: nil)
                } else {
                    // Fallback: use key equivalent for Cmd+N
                    let event = NSEvent.keyEvent(
                        with: .keyDown,
                        location: .zero,
                        modifierFlags: .command,
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: 0,
                        context: nil,
                        characters: "n",
                        charactersIgnoringModifiers: "n",
                        isARepeat: false,
                        keyCode: 45
                    )
                    if let event = event {
                        NSApp.sendEvent(event)
                    }
                }

                // After a short delay, try to find and show the window
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if let window = NSApp.windows.first(where: {
                        $0.canBecomeKey &&
                        $0.level == .normal &&
                        !$0.className.contains("StatusBar") &&
                        !$0.title.contains("Settings")
                    }) {
                        window.makeKeyAndOrderFront(nil)
                        window.orderFrontRegardless()
                    }
                }
            }
        }
    }
}
