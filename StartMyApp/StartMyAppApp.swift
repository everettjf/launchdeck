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
                Button("Email Support") {
                    sendSupportEmail()
                }
                Button("\(Bundle.main.appDisplayName) Help") {
                    if let url = URL(string: "https://startmy.app") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        Settings {
            SettingsView()
                .environmentObject(preferences)
        }
    }

    private func sendSupportEmail() {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        var deviceModel = "Unknown"
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        deviceModel = String(cString: model)

        let subject = "Feedback-StartMyApp"
        let body = """


        ---
        App Version: \(appVersion) (\(buildNumber))
        macOS Version: \(osVersion)
        Device Model: \(deviceModel)
        """

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        if let url = URL(string: "mailto:xnuapp@gmail.com?subject=\(encodedSubject)&body=\(encodedBody)") {
            NSWorkspace.shared.open(url)
        }
    }
}
