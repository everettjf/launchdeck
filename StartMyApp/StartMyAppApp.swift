import AppKit
import SwiftUI

@main
struct StartMyAppApp: App {
    @StateObject private var preferences: AppPreferences
    @StateObject private var appState: AppState
    @StateObject private var shortcutCoordinator: ShortcutCoordinator
    @StateObject private var statusItemCoordinator: StatusItemCoordinator

    init() {
        let preferences = AppPreferences()
        _preferences = StateObject(wrappedValue: preferences)
        let appState = AppState(preferences: preferences)
        _appState = StateObject(wrappedValue: appState)
        _shortcutCoordinator = StateObject(wrappedValue: ShortcutCoordinator(preferences: preferences,
                                                                             appState: appState))
        _statusItemCoordinator = StateObject(wrappedValue: StatusItemCoordinator(preferences: preferences,
                                                                                appState: appState))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(preferences)
                .frame(minWidth: 720, minHeight: 520)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(String(format: NSLocalizedString("About %@", comment: "About menu title"), Bundle.main.appDisplayName)) {
                    AboutWindowController.shared.show()
                }
            }

            CommandGroup(after: .newItem) {
                Toggle("Show System Applications", isOn: preferences.showSystemAppsBinding)
                Toggle("Show Recent Launches", isOn: $preferences.showRecentApps)
                Divider()
                Picker("Grid Size", selection: $preferences.gridScale) {
                    ForEach(AppPreferences.GridScale.allCases, id: \.self) { scale in
                        Text(scale.title).tag(scale)
                    }
                }
                Divider()
                Button("Clear Recent Launches", action: appState.clearRecents)
                Button("Export Applications to JSON…") {
                    appState.exportAppCatalog()
                }
            }

            CommandGroup(replacing: .help) {
                Button("\(Bundle.main.appDisplayName) Help") {
                    if let url = URL(string: "https://startmy.app") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }
        Settings {
            SettingsView()
                .environmentObject(preferences)
        }
    }
}
