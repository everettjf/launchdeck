import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class RecipeStudioStore {
    enum Mode: String, CaseIterable { case outline = "Outline", canvas = "Canvas" }

    var workflow: WorkflowDefinition
    var selectedNodeID: UUID?
    var selectedEdgeID: UUID?
    var mode: Mode = .outline
    var libraryQuery = ""
    var consoleIsVisible = true
    var copilotPrompt = ""
    var copilotDraft: WorkflowCopilotDraft?
    var isGenerating = false
    var isRunning = false
    var lastReceipt: WorkflowExecutionReceipt?
    var message: String?
    var AIAvailability: WorkflowAIAvailability?
    private var snapshots: [WorkflowDefinition] = []
    private var redoSnapshots: [WorkflowDefinition] = []

    init(workflow: WorkflowDefinition = WorkflowDefinition(name: "Untitled Recipe")) {
        self.workflow = workflow
    }

    func load(_ recipe: Recipe) {
        snapshots.removeAll(); redoSnapshots.removeAll()
        workflow = recipe.resolvedWorkflow
        selectedNodeID = nil; selectedEdgeID = nil
        message = recipe.workflow == nil ? "Legacy Recipe migrated to Schema v2. Save to keep the upgrade." : nil
    }

    var validationIssues: [WorkflowValidationIssue] { WorkflowValidator.validate(workflow) }
    var canRun: Bool { !workflow.nodes.isEmpty && !validationIssues.contains { $0.severity == .error } && !isRunning }
    var selectedNode: WorkflowNode? { workflow.nodes.first { $0.id == selectedNodeID } }
    var filteredDefinitions: [WorkflowNodeDefinition] {
        guard !libraryQuery.isEmpty else { return WorkflowNodeCatalog.definitions }
        return WorkflowNodeCatalog.definitions.filter {
            $0.title.localizedCaseInsensitiveContains(libraryQuery) ||
            $0.summary.localizedCaseInsensitiveContains(libraryQuery)
        }
    }

    func add(_ definition: WorkflowNodeDefinition) {
        checkpoint()
        let point = WorkflowPoint(x: 100, y: Double(workflow.nodes.count) * 150 + 80)
        let node = WorkflowNode(kindIdentifier: definition.id, position: point)
        if let previous = workflow.nodes.last,
           WorkflowNodeCatalog.definition(for: previous.kindIdentifier)?.outputs.contains(where: { $0.id == "control" }) == true,
           definition.inputs.contains(where: { $0.id == "control" }) {
            workflow.edges.append(.init(sourceNodeID: previous.id, sourcePortID: "control",
                                        targetNodeID: node.id, targetPortID: "control"))
        }
        workflow.nodes.append(node)
        selectedNodeID = node.id
    }

    func removeSelection() {
        guard let selectedNodeID else { return }
        checkpoint()
        workflow.nodes.removeAll { $0.id == selectedNodeID }
        workflow.edges.removeAll { $0.sourceNodeID == selectedNodeID || $0.targetNodeID == selectedNodeID }
        self.selectedNodeID = nil
    }

    func duplicateSelection() {
        guard let source = selectedNode else { return }
        checkpoint()
        let node = WorkflowNode(kindIdentifier: source.kindIdentifier, title: source.title + " Copy",
                                configuration: source.configuration,
                                position: .init(x: source.position.x + 36, y: source.position.y + 36),
                                isEnabled: source.isEnabled, failurePolicy: source.failurePolicy,
                                retryCount: source.retryCount)
        workflow.nodes.append(node)
        selectedNodeID = node.id
    }

    func move(from offsets: IndexSet, to destination: Int) {
        checkpoint()
        workflow.nodes.move(fromOffsets: offsets, toOffset: destination)
        rebuildControlFlow()
    }

    func updateSelected(_ transform: (inout WorkflowNode) -> Void) {
        guard let selectedNodeID, let index = workflow.nodes.firstIndex(where: { $0.id == selectedNodeID }) else { return }
        checkpoint()
        transform(&workflow.nodes[index])
    }

    func connect(sourceNodeID: UUID, sourcePortID: String, targetNodeID: UUID, targetPortID: String) {
        let edge = WorkflowEdge(sourceNodeID: sourceNodeID, sourcePortID: sourcePortID,
                                targetNodeID: targetNodeID, targetPortID: targetPortID)
        if let candidate = WorkflowGraphEditor.connecting(edge, in: workflow) {
            checkpoint(); workflow = candidate; selectedEdgeID = edge.id
        } else { message = "That connection would create a cycle or a type mismatch." }
    }

    func removeEdge(_ id: UUID) { checkpoint(); workflow.edges.removeAll { $0.id == id } }
    func autoLayout() { checkpoint(); workflow = WorkflowGraphEditor.automaticLayout(workflow) }
    func undo() { guard let prior = snapshots.popLast() else { return }; redoSnapshots.append(workflow); workflow = prior }
    func redo() { guard let next = redoSnapshots.popLast() else { return }; snapshots.append(workflow); workflow = next }

    func save(to store: RecipeStore) {
        do { try store.save(Recipe(workflow: workflow)); message = "Recipe saved." }
        catch { message = error.localizedDescription }
    }

    func run(using engine: WorkflowExecutionEngine) async {
        guard canRun else { message = validationIssues.first?.message ?? "Workflow cannot run."; return }
        isRunning = true
        lastReceipt = await engine.run(workflow)
        isRunning = false
        message = lastReceipt?.succeeded == true ? "Run completed." : "Run failed."
    }

    func generate(using service: WorkflowAIService) async {
        guard !copilotPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isGenerating = true
        defer { isGenerating = false }
        do {
            copilotDraft = try await service.createDraft(description: copilotPrompt,
                                                         policy: workflow.policy,
                                                         pccApproved: workflow.policy.dataPolicy == .privateCloudAllowed)
        } catch { message = error.localizedDescription }
    }

    func refreshAIAvailability(using service: WorkflowAIService) async {
        AIAvailability = await service.availability()
    }

    func acceptDraft() {
        guard let draft = copilotDraft else { return }
        checkpoint(); workflow = draft.workflow; copilotDraft = nil
    }

    private func checkpoint() { snapshots.append(workflow); snapshots = Array(snapshots.suffix(100)); redoSnapshots.removeAll() }
    private func rebuildControlFlow() {
        workflow.edges.removeAll { $0.sourcePortID == "control" && $0.targetPortID == "control" }
        for pair in zip(workflow.nodes, workflow.nodes.dropFirst()) {
            let sourceHasControl = WorkflowNodeCatalog.definition(for: pair.0.kindIdentifier)?.outputs.contains { $0.id == "control" } == true
            let targetHasControl = WorkflowNodeCatalog.definition(for: pair.1.kindIdentifier)?.inputs.contains { $0.id == "control" } == true
            if sourceHasControl && targetHasControl {
                workflow.edges.append(.init(sourceNodeID: pair.0.id, sourcePortID: "control",
                                            targetNodeID: pair.1.id, targetPortID: "control"))
            }
        }
    }
}
