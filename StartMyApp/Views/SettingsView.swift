import SwiftUI
import FoundationModels

struct SettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    private var model = SystemLanguageModel.default

    var body: some View {
        Form {
            Section {
                Toggle("Show System Applications", isOn: preferences.showSystemAppsBinding)

                Picker("Sort Order", selection: $preferences.sortOption) {
                    ForEach(AppPreferences.SortOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Toggle("Show Recent Launches", isOn: $preferences.showRecentApps)
                Toggle("Show Hidden Applications", isOn: $preferences.showHiddenApps)
            } header: {
                Text("General")
            } footer: {
                Text("System apps include built-in macOS applications. Hidden apps can still be found via search.")
                    .font(.caption)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tile Size")
                        .font(.subheadline.weight(.medium))

                    HStack(spacing: 20) {
                        ForEach(AppPreferences.GridScale.allCases, id: \.self) { scale in
                            Button {
                                preferences.gridScale = scale
                            } label: {
                                VStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: scale.iconSize * 0.24, style: .continuous)
                                        .fill(scale == preferences.gridScale ? Color.accentColor : Color.secondary.opacity(0.3))
                                        .frame(width: scale.iconSize, height: scale.iconSize)
                                    Text(scale.title)
                                        .font(.caption)
                                        .foregroundStyle(scale == preferences.gridScale ? .primary : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
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

            Section {
                HStack {
                    Text("Apple Intelligence")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    foundationModelsStatusView
                }
            } header: {
                Text("AI Features")
            } footer: {
                foundationModelsFooter
                    .font(.caption)
            }

            Section("More Apps") {
                if let url = URL(string: "https://apps.apple.com/us/app/myjsondiff/id6742816661") {
                    Link(destination: url) {
                        Label("MyJSONDiff", systemImage: "curlybraces")
                    }
                }
                if let url = URL(string: "https://apps.apple.com/us/app/scriptwidget/id1555600758") {
                    Link(destination: url) {
                        Label("ScriptWidget", systemImage: "curlybraces.square")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 600)
    }

    @ViewBuilder
    private var foundationModelsStatusView: some View {
        switch model.availability {
        case .available:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Available")
                    .foregroundStyle(.secondary)
            }
        case .unavailable(.deviceNotEligible):
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Not Supported")
                    .foregroundStyle(.secondary)
            }
        case .unavailable(.appleIntelligenceNotEnabled):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Not Enabled")
                    .foregroundStyle(.secondary)
            }
        case .unavailable(.modelNotReady):
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                Text("Downloading")
                    .foregroundStyle(.secondary)
            }
        case .unavailable:
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Unavailable")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var foundationModelsFooter: some View {
        switch model.availability {
        case .available:
            Text("AI search is available. Type '/' in the search box to use semantic search powered by Apple Intelligence.")
        case .unavailable(.deviceNotEligible):
            Text("Your device does not support Apple Intelligence. AI search features are not available.")
        case .unavailable(.appleIntelligenceNotEnabled):
            Text("Please enable Apple Intelligence in System Settings to use AI search features.")
        case .unavailable(.modelNotReady):
            Text("The AI model is currently downloading or not ready. Please try again later.")
        case .unavailable:
            Text("Apple Intelligence is unavailable. AI search features are disabled.")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppPreferences())
}
