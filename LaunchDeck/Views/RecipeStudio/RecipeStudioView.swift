import SwiftUI

struct RecipeStudioView: View {
    @EnvironmentObject private var appState: AppState
    @State private var studio = RecipeStudioStore()
    @State private var showsCopilot = false

    var body: some View {
        @Bindable var studio = studio
        NavigationSplitView {
            library
        } detail: {
            VStack(spacing: 0) {
                if studio.mode == .outline { outline } else { WorkflowGraphCanvasView(studio: studio) }
                if studio.consoleIsVisible { console }
            }
            .inspector(isPresented: .constant(true)) { inspector.frame(minWidth: 270, idealWidth: 310) }
        }
        .navigationTitle(studio.workflow.name)
        .toolbar { toolbar }
        .sheet(isPresented: $showsCopilot) { copilot }
        .task { await studio.refreshAIAvailability(using: appState.workflowAIService) }
        .onDeleteCommand {
            if let edgeID = studio.selectedEdgeID { studio.removeEdge(edgeID); studio.selectedEdgeID = nil }
            else { studio.removeSelection() }
        }
        .alert("Recipe Studio", isPresented: Binding(get: { studio.message != nil }, set: { if !$0 { studio.message = nil } })) {
            Button("OK") { studio.message = nil }
        } message: { Text(studio.message ?? "") }
    }

    private var library: some View {
        List {
            if !appState.recipeStore.recipes.isEmpty {
                Section("My Recipes") {
                    ForEach(appState.recipeStore.recipes) { recipe in
                        Button { studio.load(recipe) } label: {
                            Label(recipe.name, systemImage: recipe.workflow == nil ? "list.number" : "point.3.connected.trianglepath.dotted")
                        }.buttonStyle(.plain)
                    }
                }
            }
            ForEach(WorkflowNodeDefinition.Category.allCases, id: \.self) { category in
                let definitions = studio.filteredDefinitions.filter { $0.category == category }
                if !definitions.isEmpty {
                    Section(category.rawValue.capitalized) {
                        ForEach(definitions) { definition in
                            Button { studio.add(definition) } label: {
                                Label {
                                    VStack(alignment: .leading) {
                                        Text(definition.title)
                                        Text(definition.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                } icon: { Image(systemName: definition.systemImage) }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .searchable(text: Bindable(studio).libraryQuery, prompt: "Find blocks")
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    }

    private var outline: some View {
        List(selection: Bindable(studio).selectedNodeID) {
            ForEach(Array(studio.workflow.nodes.enumerated()), id: \.element.id) { index, node in
                let definition = WorkflowNodeCatalog.definition(for: node.kindIdentifier)
                HStack(spacing: 12) {
                    Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24)
                    Image(systemName: definition?.systemImage ?? "square.dashed").frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(node.title).font(.headline)
                        Text(definition?.summary ?? node.kindIdentifier).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let issue = studio.validationIssues.first(where: { $0.nodeID == node.id }) {
                        Image(systemName: issue.severity == .error ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(issue.severity == .error ? .red : .orange)
                            .help(issue.message)
                    }
                    Toggle("Enabled", isOn: Binding(get: { node.isEnabled }, set: { value in studio.selectedNodeID = node.id; studio.updateSelected { $0.isEnabled = value } }))
                        .labelsHidden()
                }
                .padding(.vertical, 7)
                .tag(node.id)
                .accessibilityLabel("Step \(index + 1), \(node.title)")
            }
            .onMove(perform: studio.move)
        }
        .overlay { if studio.workflow.nodes.isEmpty { ContentUnavailableView("Build your first recipe", systemImage: "square.stack.3d.up", description: Text("Choose blocks from the library or ask Workflow Copilot.")) } }
    }

    @ViewBuilder private var inspector: some View {
        Form {
            Section("Recipe") {
                TextField("Name", text: Binding(get: { studio.workflow.name }, set: { studio.workflow.name = $0 }))
                Picker("Model", selection: Binding(get: { studio.workflow.policy.modelPolicy }, set: { studio.workflow.policy.modelPolicy = $0 })) {
                    ForEach(WorkflowModelPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Data", selection: Binding(get: { studio.workflow.policy.dataPolicy }, set: { studio.workflow.policy.dataPolicy = $0 })) {
                    ForEach(WorkflowDataPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Dry run before mutations", isOn: Binding(get: { studio.workflow.policy.requiresDryRunBeforeMutation }, set: { studio.workflow.policy.requiresDryRunBeforeMutation = $0 }))
                Toggle("Rollback on failure", isOn: Binding(get: { studio.workflow.policy.rollbackOnFailure }, set: { studio.workflow.policy.rollbackOnFailure = $0 }))
                if studio.workflow.policy.dataPolicy != .localOnly {
                    Label("Selected block inputs may be sent to your configured provider. API keys stay in Keychain; prompts and responses are not saved in AI history.", systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let availability = studio.AIAvailability {
                Section("AI") {
                    LabeledContent("On device", value: availability.onDevice)
                    LabeledContent("External provider", value: appState.AIProviderSettings.configuration.isEnabled ? appState.AIProviderSettings.configuration.name : "Disabled")
                    LabeledContent("Local AI history", value: "\(appState.workflowAITranscriptStore.entries.count) metadata records")
                    Button("Clear AI History", role: .destructive) { appState.workflowAITranscriptStore.clear() }
                }
            }
            AIProviderSettingsView(store: appState.AIProviderSettings)
            Section("Variables") {
                ForEach(Array(studio.workflow.variables.enumerated()), id: \.element.id) { index, variable in
                    VStack(alignment: .leading) {
                        HStack {
                            TextField("Name", text: Binding(get: { variable.name }, set: { studio.workflow.variables[index].name = $0 }))
                            Picker("Type", selection: Binding(get: { variable.valueType }, set: { studio.workflow.variables[index].valueType = $0 })) {
                                ForEach(RecipeVariable.ValueType.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                            }.labelsHidden().frame(width: 95)
                            Button("Remove", systemImage: "minus.circle", role: .destructive) { studio.workflow.variables.remove(at: index) }.labelStyle(.iconOnly)
                        }
                        TextField("Default value", text: Binding(get: { variable.defaultValue }, set: { studio.workflow.variables[index].defaultValue = $0 }))
                    }
                }
                Button("Add Variable", systemImage: "plus") {
                    studio.workflow.variables.append(.init(name: "variable\(studio.workflow.variables.count + 1)"))
                }
            }
            if !studio.workflow.variables.isEmpty {
                Section("Run Inputs") {
                    ForEach(studio.workflow.variables) { variable in
                        TextField(variable.name, text: Binding(
                            get: { studio.runVariableValues[variable.name] ?? variable.defaultValue },
                            set: { studio.runVariableValues[variable.name] = $0 }
                        ))
                    }
                }
            }
            if let node = studio.selectedNode {
                Section("Selected Block") {
                    TextField("Title", text: Binding(get: { node.title }, set: { value in studio.updateSelected { $0.title = value } }))
                    Stepper("Retries: \(node.retryCount)", value: Binding(get: { node.retryCount }, set: { value in studio.updateSelected { $0.retryCount = value } }), in: 0...5)
                    Picker("On failure", selection: Binding(get: { node.failurePolicy }, set: { value in studio.updateSelected { $0.failurePolicy = value } })) {
                        Text("Stop").tag(RecipeStep.FailurePolicy.stop)
                        Text("Continue").tag(RecipeStep.FailurePolicy.continueNext)
                    }
                    configurationEditor(node)
                    HStack { Button("Duplicate", action: studio.duplicateSelection); Button("Delete", role: .destructive, action: studio.removeSelection) }
                }
                if let definition = WorkflowNodeCatalog.definition(for: node.kindIdentifier) {
                    Section("Typed Ports") {
                        ForEach(definition.inputs) { port in Label { Text(verbatim: "\(port.name): \(port.valueType)") } icon: { Image(systemName: "arrow.right.circle") } }
                        ForEach(definition.outputs) { port in Label { Text(verbatim: "\(port.name): \(port.valueType)") } icon: { Image(systemName: "arrow.left.circle") } }
                    }
                }
            } else if !studio.workflow.edges.isEmpty {
                Section("Connections") {
                    ForEach(studio.workflow.edges) { edge in
                        Button {
                            studio.selectedEdgeID = edge.id
                        } label: {
                            HStack {
                                Text(connectionTitle(edge)).lineLimit(1)
                                Spacer()
                                if studio.selectedEdgeID == edge.id { Image(systemName: "checkmark") }
                            }
                        }.buttonStyle(.plain)
                    }
                    if let edgeID = studio.selectedEdgeID {
                        Button("Delete Connection", role: .destructive) { studio.removeEdge(edgeID); studio.selectedEdgeID = nil }
                    }
                }
            }
        }.formStyle(.grouped)
    }

    @ViewBuilder private func configurationEditor(_ node: WorkflowNode) -> some View {
        if node.kindIdentifier == "data.text" {
            TextField("Text value", text: configBinding("value", node: node), axis: .vertical).lineLimit(3...8)
        }
        if node.kindIdentifier.hasPrefix("ai.") {
            TextField("AI instructions", text: configBinding("prompt", node: node), axis: .vertical).lineLimit(3...8)
        }
        if node.kindIdentifier == "data.folder" || node.kindIdentifier == "action.move" {
            TextField("Folder path", text: configBinding(node.kindIdentifier == "action.move" ? "target" : "value", node: node))
        }
        if node.kindIdentifier == "logic.delay" {
            TextField("Seconds", value: numberConfigBinding("seconds", node: node), format: .number)
        }
        if node.kindIdentifier == "logic.approval" {
            Toggle("Approved for this run", isOn: boolConfigBinding("approved", node: node))
        }
        if node.kindIdentifier == "input.files" {
            TextField("One file or folder path per line", text: objectPathsBinding(node: node), axis: .vertical).lineLimit(3...8)
        }
        if node.kindIdentifier == "action.open-application" {
            TextField("Bundle identifier", text: configBinding("identifier", node: node))
        }
        if node.kindIdentifier == "action.open-terminal" {
            TextField("Directory", text: configBinding("directory", node: node))
        }
        if node.kindIdentifier == "action.run-shortcut" {
            TextField("Shortcut name", text: configBinding("shortcut", node: node))
        }
        if node.kindIdentifier.hasPrefix("ai.") {
            if studio.workflow.policy.dataPolicy != .localOnly {
                Toggle("Approve external provider for this block", isOn: boolConfigBinding("providerApproved", node: node))
                Text("The run receipt records whether this block used on-device AI or the configured provider.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var console: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text("Validation & Run Log").font(.headline); Spacer(); Text("\(studio.validationIssues.count) issues").foregroundStyle(.secondary) }
            if studio.validationIssues.isEmpty { Label("Ready to run", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            else { ForEach(studio.validationIssues.prefix(4)) { issue in Label(issue.message, systemImage: issue.severity == .error ? "xmark.circle" : "exclamationmark.triangle").foregroundStyle(issue.severity == .error ? .red : .orange) } }
            if let receipt = studio.lastReceipt {
                HStack {
                    Text("Last run: \(receipt.succeeded ? "Succeeded" : "Failed") · \(receipt.nodes.count) blocks · \(receipt.completedAt.formatted(date: .omitted, time: .standard))").font(.caption.monospaced())
                    Spacer()
                    if receipt.canUndo { Button("Undo Run") { studio.undoLastRun(using: appState.workflowExecutionEngine) } }
                    if receipt.canRedo { Button("Redo Run") { Task { await studio.redoLastRun(using: appState.workflowExecutionEngine) } } }
                }
                ForEach(receipt.nodes.suffix(4)) { node in
                    Text("\(node.title): \(node.outcome) · \(node.route.rawValue) · \(node.duration.formatted(.number.precision(.fractionLength(3))))s")
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
            if let preview = studio.lastDryRun, !preview.mutations.isEmpty {
                Text("Dry run: \(preview.orderedNodeIDs.count) blocks · mutations: \(preview.mutations.joined(separator: ", ")) · tools: \(preview.requiredTools.sorted().joined(separator: ", "))")
                    .font(.caption.monospaced()).lineLimit(2)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.bar).frame(maxHeight: 150)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Picker("Editor", selection: Bindable(studio).mode) { ForEach(RecipeStudioStore.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            Button("Copilot", systemImage: "sparkles") { showsCopilot = true }
            Button("Auto Layout", systemImage: "wand.and.stars") { studio.autoLayout() }.disabled(studio.mode != .canvas)
            Button("Console", systemImage: "rectangle.bottomthird.inset.filled") { studio.consoleIsVisible.toggle() }
            Button("Undo", systemImage: "arrow.uturn.backward") { studio.undo() }.keyboardShortcut("z").labelStyle(.iconOnly)
            Button("Redo", systemImage: "arrow.uturn.forward") { studio.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).labelStyle(.iconOnly)
            Button("Save", systemImage: "square.and.arrow.down") { studio.save(to: appState.recipeStore) }.keyboardShortcut("s")
            Button("Dry Run", systemImage: "checklist") { studio.dryRun(using: appState.workflowExecutionEngine) }
            if studio.isRunning {
                Button("Cancel", systemImage: "stop.fill") { studio.cancel(using: appState.workflowExecutionEngine) }
            } else {
                Button("Run", systemImage: "play.fill") { Task { await studio.run(using: appState.workflowExecutionEngine) } }.disabled(!studio.canRun)
            }
        }
    }

    private var copilot: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Workflow Copilot").font(.title2.bold())
            Text("Describe the result you want. Copilot proposes only registered, typed blocks; review the diff before accepting.").foregroundStyle(.secondary)
            TextEditor(text: Bindable(studio).copilotPrompt).frame(height: 100).overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
            if let draft = studio.copilotDraft {
                GroupBox("Proposed: \(draft.workflow.name)") {
                    VStack(alignment: .leading) {
                        Text("\(draft.workflow.nodes.count) blocks")
                        ForEach(draft.workflow.nodes) { Text("• \($0.title)") }
                        ForEach(draft.assumptions, id: \.self) { Text("Assumption: \($0)").foregroundStyle(.orange) }
                        ForEach(draft.unresolvedInputs, id: \.self) { Text("Needs input: \($0)").foregroundStyle(.red) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack { Spacer(); Button("Cancel") { showsCopilot = false }; if studio.copilotDraft != nil { Button("Accept Draft") { studio.acceptDraft(); showsCopilot = false }.buttonStyle(.borderedProminent) } else { Button(studio.isGenerating ? "Generating…" : "Generate") { Task { await studio.generate(using: appState.workflowAIService) } }.buttonStyle(.borderedProminent).disabled(studio.isGenerating) } }
        }.padding(24).frame(width: 560)
    }

    private func configBinding(_ key: String, node: WorkflowNode) -> Binding<String> { Binding(get: { node.configuration[key]?.stringValue ?? "" }, set: { value in studio.updateSelected { $0.configuration[key] = .text(value) } }) }
    private func numberConfigBinding(_ key: String, node: WorkflowNode) -> Binding<Double> { Binding(get: { if case .number(let value) = node.configuration[key] { value } else { 1 } }, set: { value in studio.updateSelected { $0.configuration[key] = .number(value) } }) }
    private func boolConfigBinding(_ key: String, node: WorkflowNode) -> Binding<Bool> { Binding(get: { node.configuration[key] == .boolean(true) }, set: { value in studio.updateSelected { $0.configuration[key] = .boolean(value) } }) }
    private func objectPathsBinding(node: WorkflowNode) -> Binding<String> {
        Binding(get: { node.configuration["objects"]?.stringValue ?? "" }, set: { value in
            let paths = value.split(whereSeparator: \.isNewline).map(String.init)
            studio.updateSelected { selected in
                selected.configuration["objects"] = .collection(paths.map { path in
                    var isDirectory: ObjCBool = false
                    FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                    return isDirectory.boolValue ? .folder(path) : .file(path)
                })
            }
        })
    }

    private func connectionTitle(_ edge: WorkflowEdge) -> String {
        let source = studio.workflow.nodes.first { $0.id == edge.sourceNodeID }?.title ?? "Missing"
        let target = studio.workflow.nodes.first { $0.id == edge.targetNodeID }?.title ?? "Missing"
        return "\(source).\(edge.sourcePortID) → \(target).\(edge.targetPortID)"
    }
}

private extension WorkflowModelPolicy {
    var title: String { switch self { case .automatic: "Automatic"; case .onDeviceOnly: "On-device only"; case .preferOnDevice: "Prefer on-device"; case .externalProvider: "External provider" } }
}

private extension WorkflowDataPolicy {
    var title: String { switch self { case .localOnly: "Local only"; case .externalProviderAllowed: "External provider allowed"; case .askEveryTime: "Ask every time" } }
}
