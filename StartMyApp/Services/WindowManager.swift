import AppKit

final class WindowManager {
    static let shared = WindowManager()

    private init() {}

    func showMainWindow(completion: (() -> Void)? = nil) {
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

                // Make sure the window is visible and unhidden
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }

                // Bring window to front
                window.orderFrontRegardless()

                // Activate the app and make window key
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)

                // Force window to be main
                if !window.isKeyWindow {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        window.makeKey()
                    }
                }

                // Give the window time to become key before calling completion
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    completion?()
                }
            } else {
                // No window found, try to create a new one using Cmd+N

                // Try to trigger new window via menu
                if let newMenuItem = NSApp.mainMenu?.item(withTitle: "File")?.submenu?.item(withTitle: "New"),
                   let action = newMenuItem.action {
                    NSApp.sendAction(action, to: newMenuItem.target, from: nil)
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

                        // Give the window time to appear before calling completion
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            completion?()
                        }
                    } else {
                        completion?()
                    }
                }
            }
        }
    }
}
