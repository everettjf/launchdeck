import AppKit
import Combine
import SwiftUI
import LaunchDeckCore

struct LauncherQuickActions: View {
    let onShowLibrary: () -> Void
    let onInstantSend: () -> Void
    let onOpenRecipeStudio: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            LauncherActionButton(title: "Browse Apps",
                                 subtitle: "Full library",
                                 systemImage: "square.grid.2x2",
                                 action: onShowLibrary)
            LauncherActionButton(title: "Instant Send",
                                 subtitle: "Current selection",
                                 systemImage: "paperplane",
                                 action: onInstantSend)
            LauncherActionButton(title: "Recipe Studio",
                                 subtitle: "Automations",
                                 systemImage: "square.stack.3d.up",
                                 action: onOpenRecipeStudio)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick actions")
    }
}

struct LauncherActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(isHovering ? 0.08 : 0.035),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct SearchKindFilterMenu: View {
    @Binding var selectedKinds: Set<SearchItemKind>

    var body: some View {
        Menu {
            Button("All Results") {
                selectedKinds = Set(SearchItemKind.allCases)
            }
            Divider()
            ForEach(SearchItemKind.allCases, id: \.self) { kind in
                Button {
                    toggle(kind)
                } label: {
                    if selectedKinds.contains(kind) {
                        Label(kind.displayName, systemImage: "checkmark")
                    } else {
                        Text(kind.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .frame(width: 16, height: 16)
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.bordered)
        .help("Filter search results")
        .accessibilityLabel("Filter search results")
    }

    private func toggle(_ kind: SearchItemKind) {
        if selectedKinds == Set(SearchItemKind.allCases) {
            selectedKinds = [kind]
        } else if selectedKinds.contains(kind) {
            selectedKinds.remove(kind)
            if selectedKinds.isEmpty { selectedKinds = Set(SearchItemKind.allCases) }
        } else {
            selectedKinds.insert(kind)
        }
    }
}

struct LibraryHeader: View {
    let appCount: Int
    @Binding var sortOption: AppPreferences.SortOption
    let onRefresh: () -> Void
    let onNewFolder: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Application Library")
                .font(.title2.weight(.semibold))
            Text("\(appCount)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Picker("Sort", selection: $sortOption) {
                ForEach(AppPreferences.SortOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: 130)
            Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                .labelStyle(.iconOnly)
                .help("Refresh applications")
            Button("New Folder", systemImage: "folder.badge.plus", action: onNewFolder)
                .help("Create a new folder")
        }
    }
}

struct LauncherKeyboardFooter: View {
    let isSearching: Bool
    let isSemanticSearching: Bool

    var body: some View {
        HStack(spacing: 16) {
            if isSearching {
                KeyboardHint(keys: "↑↓", label: "Select")
                KeyboardHint(keys: "↩", label: "Open")
                KeyboardHint(keys: "⌘K", label: "Actions")
                KeyboardHint(keys: "Space", label: "Preview")
            } else {
                KeyboardHint(keys: "Type", label: "Search")
                KeyboardHint(keys: "/", label: "AI intent")
            }
            Spacer()
            if isSemanticSearching {
                ProgressView().controlSize(.mini)
                Text("Understanding intent")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 32)
        .background(.thinMaterial)
        .accessibilityElement(children: .combine)
    }
}

struct KeyboardHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.primary)
            Text(label)
        }
    }
}
