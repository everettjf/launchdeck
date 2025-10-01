import SwiftUI
import AppKit

struct FolderTile: View {
    let itemID: String
    let folder: AppCollectionItem.Folder
    var isDropTarget: Bool = false
    var onSizeChange: ((CGSize) -> Void)? = nil

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var preferences: AppPreferences

    @State private var isHovering = false
    @State private var isOpen = false
    @State private var isRenaming = false
    @State private var draftName: String

    init(itemID: String,
         folder: AppCollectionItem.Folder,
         isDropTarget: Bool = false,
         onSizeChange: ((CGSize) -> Void)? = nil) {
        self.itemID = itemID
        self.folder = folder
        self._draftName = State(initialValue: folder.name)
        self.isDropTarget = isDropTarget
        self.onSizeChange = onSizeChange
    }

    private var iconSize: CGFloat {
        preferences.gridScale.iconSize
    }

    private var tileWidth: CGFloat {
        preferences.gridScale.minimumTileWidth + 8
    }

    private var apps: [DiscoveredApp] {
        folder.appIdentifiers.compactMap { appState.app(for: $0) }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                isOpen.toggle()
            } label: {
                VStack(spacing: 10) {
                    FolderPreviewGrid(appIdentifiers: folder.appIdentifiers,
                                       iconSize: iconSize * 0.78)
                        .frame(width: iconSize + 12, height: iconSize + 12)
                    VStack(spacing: 2) {
                        if isRenaming {
                            TextField("Folder Name", text: $draftName, onCommit: commitRename)
                                .textFieldStyle(.plain)
                                .font(.system(size: preferences.gridScale.labelFontSize, weight: .semibold))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(folder.name)
                                .font(.system(size: preferences.gridScale.labelFontSize, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Text("\(folder.appIdentifiers.count) apps")
                            .font(.system(size: max(9, preferences.gridScale.labelFontSize - 1)))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(16)
                .frame(width: tileWidth)
                .background(tileBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: shadowColor, radius: isHovering ? 10 : 3, x: 0, y: isHovering ? 8 : 3)
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isHovering)
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { onSizeChange?(geometry.size) }
                    .onChange(of: geometry.size) { newSize in
                        onSizeChange?(newSize)
                    }
            }
        )
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            FolderPopoverContent(folder: folder,
                                 itemID: itemID,
                                 isRenaming: $isRenaming,
                                 draftName: $draftName)
                .environmentObject(appState)
                .environmentObject(preferences)
                .frame(width: max(360, iconSize * 3), height: 280)
        }
        .contextMenu {
            Button("Open") { isOpen = true }
            Button("Rename") {
                isRenaming = true
                isOpen = false
            }
            Button(role: .destructive) {
                appState.deleteFolder(itemID)
            } label: {
                Text("Delete Folder")
            }
        }
    }

    private func commitRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.renameFolder(id: itemID, to: trimmed)
        isRenaming = false
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(isHovering ? 0.18 : 0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isDropTarget ? Color.accentColor : Color.white.opacity(isHovering ? 0.35 : 0.12), lineWidth: isDropTarget ? 2 : 1)
            )
    }

    private var shadowColor: Color {
        Color.black.opacity(isHovering ? 0.18 : 0.08)
    }
}

private struct FolderPreviewGrid: View {
    let appIdentifiers: [String]
    let iconSize: CGFloat

    @EnvironmentObject private var appState: AppState

    var body: some View {
        let icons = Array(appIdentifiers.prefix(4))
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.12))
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    preview(for: icons.indices.contains(0) ? icons[0] : nil)
                    preview(for: icons.indices.contains(1) ? icons[1] : nil)
                }
                HStack(spacing: 2) {
                    preview(for: icons.indices.contains(2) ? icons[2] : nil)
                    preview(for: icons.indices.contains(3) ? icons[3] : nil)
                }
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private func preview(for identifier: String?) -> some View {
        if let identifier, let app = appState.app(for: identifier) {
            FolderIconView(app: app, size: iconSize / 2)
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.05))
        }
    }
}

private struct FolderIconView: View {
    let app: DiscoveredApp
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .onAppear(perform: load)
    }

    private func load() {
        AppIconCache.shared.icon(for: app.path, size: size) { image in
            self.image = image
        }
    }
}

private struct FolderPopoverContent: View {
    let folder: AppCollectionItem.Folder
    let itemID: String

    @Binding var isRenaming: Bool
    @Binding var draftName: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var preferences: AppPreferences

    private var apps: [DiscoveredApp] {
        folder.appIdentifiers.compactMap { appState.app(for: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if isRenaming {
                    TextField("Folder Name", text: $draftName, onCommit: commitRename)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                } else {
                    Text(folder.name)
                        .font(.title3.weight(.semibold))
                }
                Spacer()
                if !isRenaming {
                    Button("Rename") {
                        isRenaming = true
                    }
                } else {
                    Button("Done", action: commitRename)
                }
            }

            if apps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Empty Folder")
                        .font(.headline)
                    Text("Drag apps here to populate this folder.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(apps, id: \.identifier) { app in
                            FolderAppRow(app: app, folderID: itemID)
                                .environmentObject(appState)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(20)
    }

    private func commitRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.renameFolder(id: itemID, to: trimmed)
        isRenaming = false
    }
}

private struct FolderAppRow: View {
    let app: DiscoveredApp
    let folderID: String

    @EnvironmentObject private var appState: AppState
    @State private var icon: NSImage?

    private var iconSize: CGFloat { 36 }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.25))
                        .overlay(
                            ProgressView()
                        )
                }
            }
            .frame(width: iconSize, height: iconSize)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 14, weight: .semibold))
                Text(app.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                appState.launch(app)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .help("Launch \(app.name)")

            Button(role: .destructive) {
                appState.removeApp(app.identifier, fromFolder: folderID)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove from folder")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .onAppear(perform: loadIcon)
    }

    private func loadIcon() {
        AppIconCache.shared.icon(for: app.path, size: iconSize) { image in
            icon = image
        }
    }
}
