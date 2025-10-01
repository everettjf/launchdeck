import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        Form {
            Section("General") {
                Toggle(isOn: $preferences.showSystemApps) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show System Applications")
                        Text("Include built-in macOS apps in search results and lists.")
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
        }
        .padding(24)
        .frame(width: 420)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppPreferences())
}
