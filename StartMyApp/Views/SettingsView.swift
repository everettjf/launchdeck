import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        Form {
            Section {
                Toggle("Show System Applications", isOn: preferences.showSystemAppsBinding)

                Picker("Sort Order", selection: $preferences.sortOption) {
                    ForEach(AppPreferences.SortOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } header: {
                Text("General")
            } footer: {
                Text("System apps include built-in macOS applications.")
                    .font(.caption)
            }

            Section {
                Toggle("Show Recent Launches", isOn: $preferences.showRecentApps)
                Toggle("Show Hidden Applications", isOn: $preferences.showHiddenApps)
            } header: {
                Text("Collections")
            } footer: {
                Text("Hidden apps can still be found via search.")
                    .font(.caption)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tile Size")
                        .font(.subheadline.weight(.medium))

                    Picker("", selection: $preferences.gridScale) {
                        ForEach(AppPreferences.GridScale.allCases, id: \.self) { scale in
                            Text(scale.title).tag(scale)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    HStack(spacing: 20) {
                        ForEach(AppPreferences.GridScale.allCases, id: \.self) { scale in
                            VStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: scale.iconSize * 0.24, style: .continuous)
                                    .fill(scale == preferences.gridScale ? Color.accentColor : Color.secondary.opacity(0.3))
                                    .frame(width: scale.iconSize, height: scale.iconSize)
                                Text(scale.title)
                                    .font(.caption)
                                    .foregroundStyle(scale == preferences.gridScale ? .primary : .secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            } header: {
                Text("Appearance")
            }

            Section {
                Toggle("Show Menu Bar Icon", isOn: $preferences.showMenuBarIcon)

                Toggle("Enable Global Shortcut", isOn: $preferences.isGlobalShortcutEnabled)

                if preferences.isGlobalShortcutEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        ShortcutRecorderView(shortcut: $preferences.globalShortcut)
                        Text("Press Escape to cancel. Requires at least one modifier key.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Quick Access")
            } footer: {
                Text("Use the global shortcut to quickly open StartMyApp from anywhere.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppPreferences())
}
