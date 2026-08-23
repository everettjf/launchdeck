import AppKit
import SwiftUI

struct ObjectActionNavigatorView: View {
    private enum Stage: Int, CaseIterable { case object, action, target, preview }

    @Environment(\.dismiss) private var dismiss
    @State private var sources: [LaunchObject]
    @State private var action: ObjectAction?
    @State private var target: LaunchObject?
    @State private var stage: Stage = .object
    @State private var errorMessage: String?

    let availableTargets: (ObjectAction) -> [LaunchObject]
    let onExecute: (ObjectAction, [LaunchObject], LaunchObject?) -> Void
    let onSaveRecipe: (ObjectAction, [LaunchObject], LaunchObject?) -> Void

    init(initialSources: [LaunchObject],
         availableTargets: @escaping (ObjectAction) -> [LaunchObject],
         onExecute: @escaping (ObjectAction, [LaunchObject], LaunchObject?) -> Void,
         onSaveRecipe: @escaping (ObjectAction, [LaunchObject], LaunchObject?) -> Void) {
        _sources = State(initialValue: initialSources)
        self.availableTargets = availableTargets
        self.onExecute = onExecute
        self.onSaveRecipe = onSaveRecipe
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            breadcrumb
            Divider()
            stageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer
        }
        .padding(20)
        .frame(minWidth: 620, idealWidth: 720, minHeight: 480, idealHeight: 560)
        .onKeyPress(.tab, phases: .down) { press in
            moveStage(backward: press.modifiers.contains(.shift))
            return .handled
        }
        .alert("Action Chain", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var breadcrumb: some View {
        HStack(spacing: 8) {
            ForEach(Stage.allCases, id: \.rawValue) { item in
                Button {
                    if canVisit(item) { stage = item }
                } label: {
                    Label(title(for: item), systemImage: item == stage ? "circle.fill" : "circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(item == stage ? Color.accentColor : .secondary)
                .disabled(!canVisit(item))
                if item != .preview { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Object action target navigation")
    }

    @ViewBuilder private var stageContent: some View {
        switch stage {
        case .object: objectStage
        case .action: actionStage
        case .target: targetStage
        case .preview: previewStage
        }
    }

    private var objectStage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Objects").font(.title2.weight(.semibold))
            Text("Use multiple objects to run one batch action.").foregroundStyle(.secondary)
            List {
                ForEach(sources) { source in
                    HStack {
                        Image(systemName: icon(for: source.kind)).frame(width: 22)
                        VStack(alignment: .leading) {
                            Text(source.title)
                            Text(source.value).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("Remove", systemImage: "minus.circle", role: .destructive) {
                            sources.removeAll { $0.id == source.id }
                        }.labelStyle(.iconOnly)
                    }
                }
            }
            HStack {
                Button("Add Files…", systemImage: "plus", action: addFiles)
                Spacer()
                Text("\(sources.count) selected").foregroundStyle(.secondary)
            }
        }
    }

    private var actionStage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Action").font(.title2.weight(.semibold))
            List(ObjectActionCatalog.actions(for: sources), selection: Binding(get: { action?.id }, set: { id in
                action = ObjectAction.allCases.first { $0.id == id }; target = nil
            })) { candidate in
                Label(candidate.title, systemImage: candidate.systemImage).tag(candidate.id)
                    .accessibilityHint(candidate.requiresTarget ? "Requires a target" : "Continues to preview")
            }
        }
    }

    private var targetStage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Target").font(.title2.weight(.semibold))
            if let action {
                List(availableTargets(action), selection: Binding(get: { target?.id }, set: { id in
                    target = availableTargets(action).first { $0.id == id }
                })) { candidate in
                    Label(candidate.title, systemImage: icon(for: candidate.kind)).tag(candidate.id)
                }
                if action == .move { Button("Choose Another Folder…", action: chooseFolder) }
            }
        }
    }

    private var previewStage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Preview").font(.title2.weight(.semibold))
            if let action {
                LabeledContent("Action", value: action.title)
                LabeledContent("Objects", value: "\(sources.count)")
                if let target { LabeledContent("Target", value: target.value) }
                GroupBox("Exact inputs") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(sources) { Text($0.value).font(.caption).textSelection(.enabled) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                }
                if action.isDestructive {
                    Label("Items move to the Trash and can be restored with Undo.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel", role: .cancel) { dismiss() }
            Spacer()
            if stage != .object { Button("Back") { moveStage(backward: true) } }
            if stage == .preview, let action {
                Button("Save as Recipe") { onSaveRecipe(action, sources, target) }
                Button("Run", role: action.isDestructive ? .destructive : nil) {
                    onExecute(action, sources, target); dismiss()
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") { moveStage(backward: false) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canContinue)
            }
        }
    }

    private var canContinue: Bool {
        switch stage {
        case .object: !sources.isEmpty
        case .action: action != nil
        case .target: target != nil
        case .preview: false
        }
    }

    private func moveStage(backward: Bool) {
        if backward {
            guard stage.rawValue > 0 else { return }
            stage = Stage(rawValue: stage.rawValue - 1) ?? .object
            return
        }
        guard canContinue else { return }
        if stage == .action, action?.requiresTarget == false { stage = .preview }
        else { stage = Stage(rawValue: min(stage.rawValue + 1, Stage.preview.rawValue)) ?? .preview }
    }

    private func canVisit(_ candidate: Stage) -> Bool {
        if candidate == .object { return true }
        if candidate == .action { return !sources.isEmpty }
        if candidate == .target { return action?.requiresTarget == true }
        return action != nil && (action?.requiresTarget == false || target != nil)
    }

    private func addFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseFiles = true; panel.canChooseDirectories = true
        guard panel.runModal() == .OK else { return }
        let additions = panel.urls.map { url -> LaunchObject in
            var directory: ObjCBool = false; FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
            return LaunchObject(kind: directory.boolValue ? .folder : .file, title: url.lastPathComponent, value: url.path)
        }
        var seen = Set(sources.map(\.id)); sources += additions.filter { seen.insert($0.id).inserted }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        target = LaunchObject(kind: .folder, title: url.lastPathComponent, value: url.path)
    }

    private func title(for stage: Stage) -> String {
        switch stage { case .object: "Object"; case .action: "Action"; case .target: "Target"; case .preview: "Preview" }
    }
    private func icon(for kind: LaunchObject.Kind) -> String {
        switch kind { case .application: "app"; case .file: "doc"; case .folder: "folder"; case .url: "link"; case .text, .clipboard: "text.quote" }
    }
}
