import Combine
import Foundation

final class ShortcutCoordinator: ObservableObject {
    private let preferences: AppPreferences
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    init(preferences: AppPreferences, appState: AppState) {
        self.preferences = preferences
        self.appState = appState
        observePreferences()
        registerShortcutIfNeeded()
    }

    private func observePreferences() {
        preferences.$globalShortcut
            .combineLatest(preferences.$isGlobalShortcutEnabled)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.registerShortcutIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func registerShortcutIfNeeded() {
        if preferences.isGlobalShortcutEnabled {
            GlobalShortcutCenter.shared.register(shortcut: preferences.globalShortcut) { [weak self] in
                guard let self else { return }
                let appState = self.appState

                Task { @MainActor in
                    InstantSendService.capture { objects in
                        appState.receiveInstantSend(objects)
                        WindowManager.shared.showMainWindow {
                            Task { @MainActor in appState.postSearchFocusRequest() }
                        }
                    }
                }
            }
        } else {
            GlobalShortcutCenter.shared.unregister()
        }
    }

    deinit {
        GlobalShortcutCenter.shared.unregister()
    }
}
