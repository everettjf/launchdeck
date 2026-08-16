import AppKit
import SwiftUI

/// Shows and activates the main window.
///
/// The main window is tracked explicitly: the main scene's content registers its
/// NSWindow via WindowAccessor, and the scene's OpenWindowAction is used to
/// recreate the window after it was closed — no title/class-name heuristics and
/// no simulated Cmd+N.
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    /// Identifier of the main WindowGroup scene.
    static let mainSceneID = "main"

    private weak var mainWindow: NSWindow?
    private var openWindowAction: OpenWindowAction?

    private init() {}

    /// Called from the main scene's content when its window appears.
    func register(window: NSWindow) {
        mainWindow = window
    }

    func unregister(window: NSWindow) {
        if mainWindow == window {
            mainWindow = nil
        }
    }

    /// Called once from the main scene's content; the action stays valid for the
    /// scene and can recreate the window after it has been closed.
    func registerOpenWindowAction(_ action: OpenWindowAction) {
        openWindowAction = action
    }

    func showMainWindow(completion: (() -> Void)? = nil) {
        NSApp.activate(ignoringOtherApps: true)

        if let window = mainWindow {
            // Window exists: unhide and bring it to front
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            complete(completion, after: 0.1)
        } else if let openWindowAction {
            // Window was closed: ask the scene to recreate it
            openWindowAction(id: Self.mainSceneID)
            NSApp.activate(ignoringOtherApps: true)
            // Creating a window takes longer than raising an existing one
            complete(completion, after: 0.3)
        } else {
            completion?()
        }
    }

    private func complete(_ completion: (() -> Void)?, after delay: TimeInterval) {
        guard let completion else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            completion()
        }
    }
}
