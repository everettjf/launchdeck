import AppKit
import LaunchDeckCore
import SwiftUI

struct SearchResultRow: View {
    let item: SearchItem
    let isSelected: Bool
    let isIncluded: Bool
    let detail: String
    let commandShortcut: String?
    let onToggleIncluded: () -> Void
    let onRun: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onToggleIncluded) {
                Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isIncluded ? Color.accentColor : .secondary)
                    .padding(10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isIncluded ? "Remove from action selection" : "Add to action selection")
            Button(action: onRun) {
                HStack(spacing: 12) {
                    SearchResultIcon(item: item)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(.body.weight(.medium)).lineLimit(1)
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    SearchKindBadge(kind: item.kind, iconName: iconName)
                    if let commandShortcut {
                        Text(commandShortcut)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.16)) : AnyShapeStyle(.regularMaterial),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.8), lineWidth: 1.5)
            }
        }
        .accessibilityLabel(item.title)
        .accessibilityValue("\(item.kind.displayName), \(detail)")
        .accessibilityHint("Press Return to run or Command K for more actions")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var iconName: String {
        switch item.kind {
        case .application: "app"
        case .file: "doc"
        case .folder: "folder"
        case .project: "hammer"
        case .action: "bolt"
        case .setting: "gearshape"
        case .shortcut: "command"
        case .recipe: "list.bullet.rectangle"
        case .calculation: "function"
        case .quicklink: "link"
        case .emoji: "face.smiling"
        case .clipboard: "clipboard"
        case .snippet: "text.quote"
        case .windowAction: "macwindow"
        case .extensionCommand: "puzzlepiece.extension"
        }
    }
}

private struct SearchResultIcon: View {
    let item: SearchItem
    @State private var applicationIcon: NSImage?

    var body: some View {
        Group {
            if case .application = item.target {
                if let applicationIcon {
                    Image(nsImage: applicationIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ProgressView().controlSize(.small)
                }
            } else {
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: 34, height: 34)
        .background(Color.accentColor.opacity(item.kind == .application ? 0 : 0.1),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityHidden(true)
        .onAppear(perform: loadApplicationIcon)
        .onChange(of: item.id) { loadApplicationIcon() }
    }

    private func loadApplicationIcon() {
        guard case .application(_, let path) = item.target else {
            applicationIcon = nil
            return
        }
        AppIconCache.shared.icon(for: path, size: 34) { applicationIcon = $0 }
    }
}

private struct SearchKindBadge: View {
    let kind: SearchItemKind
    let iconName: String

    var body: some View {
        Label(kind.displayName, systemImage: iconName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.08), in: Capsule())
            .accessibilityHidden(true)
    }
}
