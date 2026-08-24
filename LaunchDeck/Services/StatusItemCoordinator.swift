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
        createStatusItem()
    }

    private func setupBindings() {
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

    private func createStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let icon = NSApp.applicationIconImage.copy() as? NSImage
            icon?.size = NSSize(width: 18, height: 18)
            icon?.isTemplate = false
            icon?.accessibilityDescription = Bundle.main.appDisplayName
            button.image = icon
            button.imagePosition = .imageOnly
            button.action = #selector(statusItemClicked(_:))
            button.target = self
        }
        statusItem = item
        refreshMenu()
    }

    private func refreshMenu() {
        guard statusItem != nil else { return }
        let menu = NSMenu()

        menu.addItem(makeMenuItem(title: "Open \(Bundle.main.appDisplayName)", action: #selector(openMainWindow)))
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
