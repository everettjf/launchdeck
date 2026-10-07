import AppKit
import Combine
import SwiftUI
import LaunchDeckCore

struct UnifiedSearchResultsView<Trailing: View>: View {
    let items: [SearchItem]
    let selectedIdentifier: String?
    let includedIdentifiers: Set<String>
    let reason: (SearchItem) -> String?
    let isCommandPressed: Bool
    let onToggleIncluded: (SearchItem) -> Void
    let onRun: (SearchItem) -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Search").font(.title2.weight(.semibold)); Spacer(); trailing() }
            LazyVStack(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    SearchResultRow(item: item,
                                    isSelected: item.id == selectedIdentifier,
                                    isIncluded: includedIdentifiers.contains(item.id),
                                    detail: reason(item) ?? item.subtitle ?? item.kind.displayName,
                                    commandShortcut: isCommandPressed ? commandShortcut(for: index) : nil) {
                        onToggleIncluded(item)
                    } onRun: {
                        onRun(item)
                    }
                }
            }
        }
    }

    private func commandShortcut(for index: Int) -> String? {
        switch index {
        case 0...8: return "⌘\(index + 1)"
        case 9: return "⌘0"
        default: return nil
        }
    }

}

struct SearchActionPanel: View {
    @Environment(\.dismiss) private var dismiss
    let item: SearchItem
    let actions: [SearchContextAction]
    let onRun: (SearchContextAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(item.title).font(.title2.weight(.semibold))
            Text(item.subtitle ?? item.kind.rawValue.capitalized).foregroundStyle(.secondary)
            if actions.isEmpty {
                ContentUnavailableView("No Available Actions", systemImage: "bolt.slash")
            } else {
                List(actions) { action in
                    Button { onRun(action) } label: {
                        HStack {
                            Label(action.title, systemImage: action.systemImage)
                            Spacer()
                            if let hint = action.keyboardHint {
                                Text(hint).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack { Spacer(); Button("Cancel", role: .cancel) { dismiss() } }
        }
        .padding(24)
        .frame(width: 440, height: 360)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actions for \(item.title)")
    }
}

struct ActionPreviewView: View {
    let preview: ActionPreview
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Action Preview", systemImage: preview.risk == .elevated ? "exclamationmark.shield" : "checkmark.shield")
                .font(.title2.weight(.semibold))
            Text(preview.title).font(.headline)
            Text(preview.summary).foregroundStyle(.secondary)
            LabeledContent("Target", value: preview.target)
            if !preview.steps.isEmpty {
                GroupBox("Steps") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(preview.steps.enumerated()), id: \.element.id) { index, step in
                            Text("\(index + 1). \(step.title)").frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.top, 4)
                }
            }
            ForEach(preview.permissions, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            HStack { Spacer(); Button("Cancel", role: .cancel, action: onCancel); Button("Run", action: onConfirm).keyboardShortcut(.defaultAction) }
        }
        .padding(24).frame(width: 520)
    }
}
