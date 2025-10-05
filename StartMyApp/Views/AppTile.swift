import AppKit
import SwiftUI

struct AppTile: View {
    let app: DiscoveredApp

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var preferences: AppPreferences

    @State private var icon: NSImage?
    @State private var isHovering = false

    var folderID: String? = nil
    var isDropTarget: Bool = false
    var isReorderTarget: Bool = false
    var onSizeChange: ((CGSize) -> Void)? = nil

    private var tileWidth: CGFloat {
        preferences.gridScale.minimumTileWidth + 8
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: { appState.launch(app) }) {
                VStack(spacing: 8) {
                    AppIcon(image: icon, size: preferences.gridScale.iconSize)
                    Text(app.name)
                        .font(.system(size: preferences.gridScale.labelFontSize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)
                        .frame(height: titleHeight, alignment: .top)
                        .help(app.name)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
                .frame(width: tileWidth)
                .background(tileBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowOffset)
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isHovering)
            .scaleEffect(scaleFactor)

            FavoriteToggleButton(isFavorite: appState.isFavorite(app)) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                    appState.toggleFavorite(for: app)
                }
            }
            .padding(.top, 8)
            .padding(.trailing, 8)
            .opacity(isHovering || appState.isFavorite(app) ? 1 : 0)
            .animation(.easeInOut(duration: 0.18), value: isHovering || appState.isFavorite(app))
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear(perform: loadIcon)
        .onChange(of: preferences.gridScale) { _, _ in
            loadIcon()
        }
        .background(SizeReader(onChange: { size in
            onSizeChange?(size)
        }))
        .contextMenu {
            Button(appState.isFavorite(app) ? "Remove from Favorites" : "Add to Favorites") {
                appState.toggleFavorite(for: app)
            }
            Divider()
            Button(appState.isHidden(app) ? "Unhide" : "Hide") {
                if appState.isHidden(app) {
                    appState.unhideApp(app)
                } else {
                    appState.hideApp(app)
                }
            }
            Divider()
            Button("Show in Finder") {
                appState.revealInFinder(app)
            }
            Button("Copy Path") {
                appState.copyPathToClipboard(app)
            }
            Button("App Info") {
                appState.presentAppInfo(for: app)
            }
            if let folderID {
                Divider()
                Button("Remove from Folder") {
                    appState.removeApp(app.identifier, fromFolder: folderID)
                }
            }
            Divider()
            if appState.recents.contains(where: { $0.identifier == app.identifier }) {
                Button("Remove from Recents") {
                    appState.removeFromRecents(app)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(app.name))
        .accessibilityAddTraits(appState.isFavorite(app) ? .isSelected : [])
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(backgroundFill)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
    }

    private var shadowColor: Color {
        if isDropTarget {
            return Color.accentColor.opacity(0.28)
        }
        if isReorderTarget {
            return Color.accentColor.opacity(0.24)
        }
        return Color.black.opacity(isHovering ? 0.18 : 0.08)
    }

    private var shadowRadius: CGFloat {
        if isDropTarget { return 18 }
        if isReorderTarget { return 14 }
        return isHovering ? 10 : 3
    }

    private var shadowOffset: CGFloat {
        if isDropTarget { return 12 }
        if isReorderTarget { return 10 }
        return isHovering ? 8 : 3
    }

    private var borderColor: Color {
        if isDropTarget { return Color.accentColor }
        if isReorderTarget { return Color.accentColor.opacity(0.75) }
        return Color.white.opacity(isHovering ? 0.35 : 0.12)
    }

    private var borderWidth: CGFloat {
        if isDropTarget { return 2.4 }
        if isReorderTarget { return 2 }
        return 1
    }

    private var backgroundFill: Color {
        if isDropTarget {
            return Color.accentColor.opacity(0.22)
        }
        if isReorderTarget {
            return Color.accentColor.opacity(0.18)
        }
        return Color.white.opacity(isHovering ? 0.18 : 0.1)
    }

    private var scaleFactor: CGFloat {
        if isDropTarget { return 1.06 }
        if isReorderTarget { return 1.04 }
        if isHovering { return 1.02 }
        return 1.0
    }

    private var titleHeight: CGFloat {
        switch preferences.gridScale {
        case .compact: return 28
        case .comfortable: return 32
        case .spacious: return 38
        }
    }

    private func loadIcon() {
        AppIconCache.shared.icon(for: app.path, size: preferences.gridScale.iconSize) { image in
            icon = image
        }
    }
}

private struct SizeReader: View {
    var onChange: (CGSize) -> Void

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear {
                    onChange(geometry.size)
                }
                .onChange(of: geometry.size) { _, newValue in
                    onChange(newValue)
                }
        }
    }
}

    private struct FavoriteToggleButton: View {
        var isFavorite: Bool
        var action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
                    .padding(4)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.borderless)
            .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        }
    }

private struct AppIcon: View {
    var image: NSImage?
    var size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: size, height: size)
                    .overlay(
                        ProgressView()
                    )
            }
        }
        .frame(width: size, height: size)
    }
}
