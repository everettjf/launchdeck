import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        Form {
            Section("General") {
                Toggle(isOn: preferences.hideSystemAppsBinding) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hide System Applications")
                        Text("Remove built-in macOS apps from search results and collections.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Sort Order", selection: $preferences.sortOption) {
                    ForEach(AppPreferences.SortOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            }

            Section("Collections") {
                Toggle(isOn: $preferences.showRecentApps) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show Recent Launches")
                        Text("Controls whether the Recently Launched section appears on the home screen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Appearance") {
                Picker("Tile Size", selection: $preferences.gridScale) {
                    ForEach(AppPreferences.GridScale.allCases, id: \.self) { scale in
                        Text(scale.title).tag(scale)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        ForEach(AppPreferences.GridScale.allCases, id: \.self) { scale in
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: scale.iconSize * 0.24, style: .continuous)
                                    .fill(scale == preferences.gridScale ? Color.accentColor.opacity(0.65) : Color.secondary.opacity(0.25))
                                    .frame(width: scale.iconSize, height: scale.iconSize)
                                Text(scale.title)
                                    .font(.system(size: 11))
                            }
                            .padding(8)
                            .frame(width: scale.minimumTileWidth)
                            .background(scale == preferences.gridScale ? Color.accentColor.opacity(0.08) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                .padding(.top, 6)
            }

            Section("Quick Access") {
                Toggle(isOn: $preferences.showMenuBarIcon) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show Menu Bar Icon")
                        Text("Provides quick access from the menu bar to launch the app and toggle key settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $preferences.isGlobalShortcutEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Global Shortcut")
                        Text("Use a keyboard shortcut to bring StartMyApp to the front and focus search.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if preferences.isGlobalShortcutEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Shortcut")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ShortcutRecorderView(shortcut: $preferences.globalShortcut)
                        Text("Press Escape to cancel while recording. At least one modifier key is required.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppPreferences())
}
