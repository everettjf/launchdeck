import AppKit
import SwiftUI

struct AppTile: View {
    let app: DiscoveredApp

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var preferences: AppPreferences

    @State private var icon: NSImage?
    @State private var isHovering = false

    private var tileWidth: CGFloat {
        preferences.gridScale.minimumTileWidth + 24
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: { appState.launch(app) }) {
                VStack(spacing: 10) {
                    AppIcon(image: icon, size: preferences.gridScale.iconSize)
                    Text(app.name)
                        .font(.system(size: preferences.gridScale.labelFontSize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                    Text(app.subtitle)
                        .font(.system(size: max(9, preferences.gridScale.labelFontSize - 1)))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .padding(16)
                .frame(width: tileWidth)
                .background(tileBackground)
                .overlay(tileBorder)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: shadowColor, radius: isHovering ? 12 : 4, x: 0, y: isHovering ? 10 : 4)
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isHovering)

            FavoriteToggleButton(isFavorite: appState.isFavorite(app)) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                    appState.toggleFavorite(for: app)
                }
            }
            .padding(12)
            .opacity(isHovering || appState.isFavorite(app) ? 1 : 0)
            .animation(.easeInOut(duration: 0.18), value: isHovering || appState.isFavorite(app))
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear(perform: loadIcon)
        .onChange(of: preferences.gridScale) { _ in
            loadIcon()
        }
        .contextMenu {
            Button(appState.isFavorite(app) ? "Remove from Favorites" : "Add to Favorites") {
                appState.toggleFavorite(for: app)
            }
            Divider()
            Button("Show in Finder") {
                appState.revealInFinder(app)
            }
            Button("Copy Path") {
                appState.copyPathToClipboard(app)
            }
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
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.16 : 0.08))
            )
    }

    private var tileBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.white.opacity(isHovering ? 0.35 : 0.15), lineWidth: isHovering ? 1.4 : 1)
    }

    private var shadowColor: Color {
        Color.black.opacity(isHovering ? 0.22 : 0.12)
    }

    private func loadIcon() {
        AppIconCache.shared.icon(for: app.path, size: preferences.gridScale.iconSize) { image in
            icon = image
        }
    }
}

private struct FavoriteToggleButton: View {
    var isFavorite: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
                .padding(6)
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
