import AppKit
import Combine
import SwiftUI
import LaunchDeckCore

struct CompactLauncherRecents: View {
    let recentApps: [DiscoveredApp]
    let onLaunch: (DiscoveredApp) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if recentApps.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "command.square")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ready when you are")
                            .font(.headline)
                        Text("Type above to find apps, files, actions, and recipes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 76)
            } else {
                HStack {
                    Text("RECENT")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                    Spacer()
                    Text("⌘1–5 to launch")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 8) {
                    ForEach(recentApps, id: \.identifier) { app in
                        CompactRecentAppButton(app: app) {
                            onLaunch(app)
                        }
                    }
                }
            }

            HStack(spacing: 14) {
                KeyboardHint(keys: "Type", label: "Search")
                KeyboardHint(keys: "/", label: "AI intent")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 11)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent applications")
    }
}

struct CompactRecentAppButton: View {
    let app: DiscoveredApp
    let action: () -> Void

    @State private var icon: NSImage?
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Group {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(width: 30, height: 30)
                Text(app.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .padding(.horizontal, 6)
            .background(Color.primary.opacity(isHovering ? 0.08 : 0.035),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .onAppear(perform: loadIcon)
        .onChange(of: app.identifier) { loadIcon() }
        .help(app.name)
        .accessibilityLabel("Open \(app.name)")
    }

    private func loadIcon() {
        AppIconCache.shared.icon(for: app.path, size: 30) { icon = $0 }
    }
}
