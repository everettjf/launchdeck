import LaunchDeckCore
import SwiftUI

struct SearchResultRow: View {
    let item: SearchItem
    let isSelected: Bool
    let isIncluded: Bool
    let detail: String
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
                Image(systemName: iconName).frame(width: 24).foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.body.weight(.medium)).lineLimit(1)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Text(item.kind.rawValue.capitalized).font(.caption2).foregroundStyle(.tertiary)
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
        .accessibilityValue("\(item.kind.rawValue.capitalized), \(detail)")
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
