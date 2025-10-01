import SwiftUI

@main
struct StartMyAppApp: App {
    @StateObject private var preferences: AppPreferences
    @StateObject private var appState: AppState

    init() {
        let preferences = AppPreferences()
        _preferences = StateObject(wrappedValue: preferences)
        _appState = StateObject(wrappedValue: AppState(preferences: preferences))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(preferences)
                .frame(minWidth: 720, minHeight: 520)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Applications", action: appState.refreshApps)
                    .keyboardShortcut("r", modifiers: [.command])
                Toggle("Show System Applications", isOn: $preferences.showSystemApps)
                Divider()
                Picker("Grid Size", selection: $preferences.gridScale) {
                    ForEach(AppPreferences.GridScale.allCases, id: \.self) { scale in
                        Text(scale.title).tag(scale)
                    }
                }
                Divider()
                Button("Clear Recent Launches", action: appState.clearRecents)
            }
            CommandMenu("Focus") {
                Button("Focus Search") {
                    appState.postSearchFocusRequest()
                }
                .keyboardShortcut("f", modifiers: [.command])
            }
        }
        Settings {
            SettingsView()
                .environmentObject(preferences)
        }
    }
}
