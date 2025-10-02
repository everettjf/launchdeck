import AppKit
import Combine

final class StatusItemCoordinator: ObservableObject {
    private var statusItem: NSStatusItem?
    private let preferences: AppPreferences
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    init(preferences: AppPreferences, appState: AppState) {
        self.preferences = preferences
        self.appState = appState
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
        }
        statusItem = item
        refreshMenu()
    }

    private func refreshMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        menu.addItem(makeMenuItem(title: "打开 StartMyApp", action: #selector(openMainWindow)))
        menu.addItem(makeMenuItem(title: "聚焦搜索", action: #selector(focusSearch)))
        menu.addItem(makeMenuItem(title: "刷新应用列表", action: #selector(refreshApplications)))
        menu.addItem(.separator())

        let recentsItem = makeMenuItem(title: "显示最近使用", action: #selector(toggleRecents))
        recentsItem.state = preferences.showRecentApps ? .on : .off
        menu.addItem(recentsItem)

        let shortcutItem = makeMenuItem(title: "启用全局快捷键", action: #selector(toggleShortcut))
        shortcutItem.state = preferences.isGlobalShortcutEnabled ? .on : .off
        menu.addItem(shortcutItem)

        if preferences.isGlobalShortcutEnabled {
            let currentShortcut = NSMenuItem(title: "当前：\(preferences.globalShortcut.displayString)", action: nil, keyEquivalent: "")
            currentShortcut.isEnabled = false
            menu.addItem(currentShortcut)
        }

        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "设置…", action: #selector(openSettings)))
        menu.addItem(makeMenuItem(title: "关于 StartMyApp", action: #selector(openAbout)))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "退出", action: #selector(terminate)))

        statusItem.menu = menu
    }

    private func makeMenuItem(title: String, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openMainWindow() {
        WindowManager.shared.showMainWindow()
    }

    @objc private func focusSearch() {
        WindowManager.shared.showMainWindow()
        Task { @MainActor in
            self.appState.postSearchFocusRequest()
        }
    }

    @objc private func refreshApplications() {
        Task { @MainActor in
            self.appState.refreshApps()
        }
    }

    @objc private func toggleRecents() {
        preferences.showRecentApps.toggle()
    }

    @objc private func toggleShortcut() {
        preferences.isGlobalShortcutEnabled.toggle()
    }

    @objc private func openSettings() {
        NSApp.presentSettings()
    }

    @objc private func openAbout() {
        AboutWindowController.shared.show()
    }

    @objc private func terminate() {
        NSApp.terminate(nil)
    }
}
