import AppKit
import Combine

final class StatusItemCoordinator: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private let preferences: AppPreferences
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    init(preferences: AppPreferences, appState: AppState) {
        self.preferences = preferences
        self.appState = appState
        super.init()
        setupBindings()
        updateStatusItemVisibility(show: preferences.showMenuBarIcon)
    }

    private func setupBindings() {
        preferences.$showMenuBarIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] show in
                self?.updateStatusItemVisibility(show: show)
            }
            .store(in: &cancellables)

        Publishers.Merge3(
            preferences.$showRecentApps.map { _ in () },
            preferences.$isGlobalShortcutEnabled.map { _ in () },
            preferences.$globalShortcut.map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.refreshMenu()
        }
        .store(in: &cancellables)
    }

    private func updateStatusItemVisibility(show: Bool) {
        if show {
            if statusItem == nil {
                createStatusItem()
            }
            refreshMenu()
        } else {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
        }
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: Bundle.main.appDisplayName)
            button.imagePosition = .imageOnly
            button.action = #selector(statusItemClicked(_:))
            button.target = self
        }
        statusItem = item
        refreshMenu()
    }

    private func refreshMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        menu.addItem(makeMenuItem(title: "Open StartMyApp", action: #selector(openMainWindow)))
        menu.addItem(.separator())

        let shortcutItem = makeMenuItem(title: "Enable Global Shortcut", action: #selector(toggleShortcut))
        shortcutItem.state = preferences.isGlobalShortcutEnabled ? .on : .off
        menu.addItem(shortcutItem)

        if preferences.isGlobalShortcutEnabled {
            let currentShortcut = NSMenuItem(title: "Current: \(preferences.globalShortcut.displayString)", action: nil, keyEquivalent: "")
            currentShortcut.isEnabled = false
            menu.addItem(currentShortcut)
        }

        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "Quit", action: #selector(terminate)))

        self.menu = menu
    }

    private func makeMenuItem(title: String, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openMainWindow() {
        WindowManager.shared.showMainWindow()
    }

    @objc private func toggleShortcut() {
        preferences.isGlobalShortcutEnabled.toggle()
    }

    @objc private func terminate() {
        NSApp.terminate(nil)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let menu = menu, let button = statusItem?.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }
}
