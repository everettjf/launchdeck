import AppKit
import Combine
import Foundation

nonisolated enum WorkflowModelRoute: String, Codable, Hashable, Sendable {
    case deterministic
    case onDevice
    case privateCloudCompute
}

nonisolated struct WorkflowUndoOperation: Codable, Hashable, Sendable {
    struct Move: Codable, Hashable, Sendable { var source: String; var destination: String }
    var title: String
    var moves: [Move]
    var createdPaths: [String]

    init(_ record: FileUndoRecord) {
        title = record.title
        moves = record.moves.map { .init(source: $0.source.path, destination: $0.destination.path) }
        createdPaths = record.createdURLs.map(\.path)
    }

    var fileRecord: FileUndoRecord {
        FileUndoRecord(title: title,
                       moves: moves.map { .init(source: URL(fileURLWithPath: $0.source), destination: URL(fileURLWithPath: $0.destination)) },
                       createdURLs: createdPaths.map(URL.init(fileURLWithPath:)))
    }
}

nonisolated struct WorkflowNodeReceipt: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let nodeID: UUID
    let title: String
    let startedAt: Date
    let duration: TimeInterval
    let outcome: String
    let route: WorkflowModelRoute
    let inputTypes: [String: WorkflowValueType]
    let outputTypes: [String: WorkflowValueType]
    let toolIDs: Set<String>
    let error: String?

    init(id: UUID, nodeID: UUID, title: String, startedAt: Date, duration: TimeInterval,
         outcome: String, route: WorkflowModelRoute, inputTypes: [String: WorkflowValueType] = [:],
         outputTypes: [String: WorkflowValueType], toolIDs: Set<String> = [], error: String?) {
        self.id = id; self.nodeID = nodeID; self.title = title; self.startedAt = startedAt
        self.duration = duration; self.outcome = outcome; self.route = route
        self.inputTypes = inputTypes; self.outputTypes = outputTypes; self.toolIDs = toolIDs; self.error = error
    }

    private enum CodingKeys: String, CodingKey {
        case id, nodeID, title, startedAt, duration, outcome, route, inputTypes, outputTypes, toolIDs, error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        title = try container.decode(String.self, forKey: .title)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        outcome = try container.decode(String.self, forKey: .outcome)
        route = try container.decode(WorkflowModelRoute.self, forKey: .route)
        inputTypes = try container.decodeIfPresent([String: WorkflowValueType].self, forKey: .inputTypes) ?? [:]
        outputTypes = try container.decodeIfPresent([String: WorkflowValueType].self, forKey: .outputTypes) ?? [:]
        toolIDs = try container.decodeIfPresent(Set<String>.self, forKey: .toolIDs) ?? []
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}

nonisolated struct WorkflowExecutionReceipt: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let workflow: WorkflowDefinition
    let startedAt: Date
    var completedAt: Date
    var succeeded: Bool
    var wasRolledBack: Bool
    var wasUndone: Bool
    var nodes: [WorkflowNodeReceipt]
    var undoOperations: [WorkflowUndoOperation]

    var canUndo: Bool { succeeded && !wasUndone && !undoOperations.isEmpty }
    var canRedo: Bool { succeeded && wasUndone }
}

nonisolated struct WorkflowNodeExecutionResult: Sendable {
    var outputs: [String: WorkflowValue]
    var route: WorkflowModelRoute
    var undoOperation: WorkflowUndoOperation?
}

nonisolated struct WorkflowDryRunReport: Hashable, Sendable {
    let issues: [WorkflowValidationIssue]
    let orderedNodeIDs: [UUID]
    let mutations: [String]
    let requiredTools: Set<String>
    var isReady: Bool { !issues.contains { $0.severity == .error } }
    var requiresConfirmation: Bool { !mutations.isEmpty }
}

@MainActor protocol WorkflowNodeExecuting {
    func execute(node: WorkflowNode, inputs: [String: WorkflowValue], workflow: WorkflowDefinition) async throws -> WorkflowNodeExecutionResult
}

@MainActor
final class WorkflowReceiptStore: ObservableObject {
    @Published private(set) var receipts: [WorkflowExecutionReceipt]
    private let defaults: UserDefaults
    private let key = "workflow.receipts.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        receipts = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([WorkflowExecutionReceipt].self, from: $0) } ?? []
    }

    func save(_ receipt: WorkflowExecutionReceipt) {
        if let index = receipts.firstIndex(where: { $0.id == receipt.id }) { receipts[index] = receipt }
        else { receipts.insert(receipt, at: 0) }
        receipts = Array(receipts.prefix(50))
        persist()
    }

    func markUndone(_ id: UUID, value: Bool) {
        guard let index = receipts.firstIndex(where: { $0.id == id }) else { return }
        receipts[index].wasUndone = value
        persist()
    }

    func clear() { receipts = []; defaults.removeObject(forKey: key) }
    private func persist() { defaults.set(try? JSONEncoder().encode(receipts), forKey: key) }
}

@MainActor
final class WorkflowExecutionEngine: ObservableObject {
    enum State: Equatable { case idle, validating, running(UUID), rollingBack, completed(UUID), cancelled, failed(String) }

    @Published private(set) var state: State = .idle
    @Published private(set) var activeNodeID: UUID?
    private let executor: any WorkflowNodeExecuting
    private let receiptStore: WorkflowReceiptStore
    private let files: FileOperationService
    private var isCancellationRequested = false
    private var activeTask: Task<WorkflowExecutionReceipt, Never>?

    init(executor: any WorkflowNodeExecuting, receiptStore: WorkflowReceiptStore,
         files: FileOperationService = FileOperationService()) {
        self.executor = executor
        self.receiptStore = receiptStore
        self.files = files
    }

    func dryRun(_ workflow: WorkflowDefinition) -> WorkflowDryRunReport {
        let issues = WorkflowValidator.validate(workflow)
        let enabledDefinitions = workflow.nodes.filter(\.isEnabled).compactMap { WorkflowNodeCatalog.definition(for: $0.kindIdentifier) }
        return .init(issues: issues,
                     orderedNodeIDs: WorkflowValidator.topologicalOrder(for: workflow) ?? [],
                     mutations: enabledDefinitions.filter(\.isMutating).map(\.title),
                     requiredTools: Set(enabledDefinitions.flatMap(\.requiredToolIDs)))
    }

    func run(_ workflow: WorkflowDefinition, variableValues: [String: String] = [:]) async -> WorkflowExecutionReceipt {
        activeTask?.cancel()
        let task = Task { await performRun(workflow, variableValues: variableValues) }
        activeTask = task
        let receipt = await task.value
        activeTask = nil
        return receipt
    }

    private func performRun(_ workflow: WorkflowDefinition,
                            variableValues: [String: String]) async -> WorkflowExecutionReceipt {
        isCancellationRequested = false
        state = .validating
        let preview = dryRun(workflow)
        let errors = preview.issues.filter { $0.severity == .error }
        guard errors.isEmpty, let order = WorkflowValidator.topologicalOrder(for: workflow) else {
            let message = errors.first?.message ?? "Workflow graph is invalid."
            state = .failed(message)
            return failedReceipt(workflow, message: message)
        }

        let receiptID = UUID()
        state = .running(receiptID)
        let startedAt = Date()
        var nodeReceipts: [WorkflowNodeReceipt] = []
        var outputs: [UUID: [String: WorkflowValue]] = [:]
        var undo: [WorkflowUndoOperation] = []
        let nodes = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
        var runtimeVariables = Dictionary(uniqueKeysWithValues: workflow.variables.map { ($0.name, $0.defaultValue) })
        runtimeVariables.merge(variableValues) { _, supplied in supplied }
        let missingVariables = requiredVariables(in: workflow).filter { runtimeVariables[$0, default: ""].isEmpty }
        if !missingVariables.isEmpty {
            let message = "Missing workflow variables: \(missingVariables.sorted().joined(separator: ", "))."
            state = .failed(message)
            return failedReceipt(workflow, message: message)
        }

        for nodeID in order {
            if Task.isCancelled || isCancellationRequested {
                let rolledBack = workflow.policy.rollbackOnFailure && rollback(undo)
                state = .cancelled
                return finish(workflow, id: receiptID, startedAt: startedAt, succeeded: false,
                              rolledBack: rolledBack, nodes: nodeReceipts, undo: undo)
            }
            guard let storedNode = nodes[nodeID], storedNode.isEnabled else { continue }
            let node = resolved(node: storedNode, variables: runtimeVariables)
            guard RecipeRunner.conditionMatches(node.condition) else {
                nodeReceipts.append(.init(id: UUID(), nodeID: node.id, title: node.title, startedAt: .now,
                                          duration: 0, outcome: "skipped", route: .deterministic,
                                          outputTypes: [:], error: nil))
                continue
            }
            activeNodeID = nodeID
            let nodeStartedAt = Date()
            let inputs = resolvedInputs(for: node, workflow: workflow, outputs: outputs)
            let toolIDs = WorkflowNodeCatalog.definition(for: node.kindIdentifier)?.requiredToolIDs ?? []
            do {
                let result = try await executeWithRetry(node: node, inputs: inputs, workflow: workflow)
                outputs[nodeID] = result.outputs
                if let outputVariable = node.outputVariable,
                   let value = result.outputs.keys.sorted().filter({ $0 != "control" }).compactMap({ result.outputs[$0]?.stringValue }).first {
                    runtimeVariables[outputVariable] = value
                }
                if let operation = result.undoOperation { undo.append(operation) }
                nodeReceipts.append(.init(id: UUID(), nodeID: node.id, title: node.title, startedAt: nodeStartedAt,
                                          duration: Date().timeIntervalSince(nodeStartedAt), outcome: "succeeded",
                                          route: result.route, inputTypes: inputs.mapValues(\.valueType),
                                          outputTypes: result.outputs.mapValues(\.valueType), toolIDs: toolIDs, error: nil))
            } catch {
                nodeReceipts.append(.init(id: UUID(), nodeID: node.id, title: node.title, startedAt: nodeStartedAt,
                                          duration: Date().timeIntervalSince(nodeStartedAt), outcome: "failed",
                                          route: .deterministic, inputTypes: inputs.mapValues(\.valueType),
                                          outputTypes: [:], toolIDs: toolIDs, error: error.localizedDescription))
                if Task.isCancelled || isCancellationRequested {
                    let rolledBack = workflow.policy.rollbackOnFailure && rollback(undo)
                    state = .cancelled
                    return finish(workflow, id: receiptID, startedAt: startedAt, succeeded: false,
                                  rolledBack: rolledBack, nodes: nodeReceipts, undo: undo)
                }
                if node.failurePolicy == .continueNext || node.isOptional { continue }
                let rolledBack = workflow.policy.rollbackOnFailure && rollback(undo)
                state = .failed(error.localizedDescription)
                return finish(workflow, id: receiptID, startedAt: startedAt, succeeded: false,
                              rolledBack: rolledBack, nodes: nodeReceipts, undo: undo)
            }
        }
        activeNodeID = nil
        let receipt = finish(workflow, id: receiptID, startedAt: startedAt, succeeded: true,
                             rolledBack: false, nodes: nodeReceipts, undo: undo)
        state = .completed(receipt.id)
        return receipt
    }

    func cancel() { isCancellationRequested = true; activeTask?.cancel() }

    func undo(_ receipt: WorkflowExecutionReceipt) throws {
        guard receipt.canUndo else { return }
        for operation in receipt.undoOperations.reversed() { try files.undo(operation.fileRecord) }
        receiptStore.markUndone(receipt.id, value: true)
    }

    func redo(_ receipt: WorkflowExecutionReceipt) async -> WorkflowExecutionReceipt? {
        guard receipt.canRedo else { return nil }
        return await run(receipt.workflow)
    }

    private func resolvedInputs(for node: WorkflowNode, workflow: WorkflowDefinition,
                                outputs: [UUID: [String: WorkflowValue]]) -> [String: WorkflowValue] {
        var values = node.configuration
        for edge in workflow.edges where edge.targetNodeID == node.id {
            if let value = outputs[edge.sourceNodeID]?[edge.sourcePortID] { values[edge.targetPortID] = value }
        }
        return values
    }

    private func resolved(node: WorkflowNode, variables: [String: String]) -> WorkflowNode {
        var result = node
        result.configuration = node.configuration.mapValues { substitute($0, variables: variables) }
        switch node.condition {
        case .fileExists(let path): result.condition = .fileExists(path: RecipeVariableResolver.substitute(path, replacements: variables))
        case .applicationRunning(let identifier): result.condition = .applicationRunning(identifier: RecipeVariableResolver.substitute(identifier, replacements: variables))
        case .valueEquals(let lhs, let rhs):
            result.condition = .valueEquals(lhs: RecipeVariableResolver.substitute(lhs, replacements: variables),
                                            rhs: RecipeVariableResolver.substitute(rhs, replacements: variables))
        case nil: break
        }
        return result
    }

    private func substitute(_ value: WorkflowValue, variables: [String: String]) -> WorkflowValue {
        switch value {
        case .text(let value): .text(RecipeVariableResolver.substitute(value, replacements: variables))
        case .url(let value): .url(RecipeVariableResolver.substitute(value, replacements: variables))
        case .file(let value): .file(RecipeVariableResolver.substitute(value, replacements: variables))
        case .folder(let value): .folder(RecipeVariableResolver.substitute(value, replacements: variables))
        case .application(let identifier, let path):
            .application(identifier: RecipeVariableResolver.substitute(identifier, replacements: variables),
                         path: RecipeVariableResolver.substitute(path, replacements: variables))
        case .object(let object):
            .object(LaunchObject(id: object.id, kind: object.kind, title: object.title,
                                 value: RecipeVariableResolver.substitute(object.value, replacements: variables),
                                 applicationIdentifier: object.applicationIdentifier))
        case .collection(let values): .collection(values.map { substitute($0, variables: variables) })
        case .structured(let values): .structured(values.mapValues { substitute($0, variables: variables) })
        default: value
        }
    }

    private func requiredVariables(in workflow: WorkflowDefinition) -> Set<String> {
        func strings(_ value: WorkflowValue) -> [String] {
            switch value {
            case .text(let value), .url(let value), .file(let value), .folder(let value): [value]
            case .application(let identifier, let path): [identifier, path]
            case .object(let object): [object.value]
            case .collection(let values): values.flatMap(strings)
            case .structured(let values): values.values.flatMap(strings)
            default: []
            }
        }
        let configured = workflow.nodes.flatMap { $0.configuration.values.flatMap(strings) }
        let conditions = workflow.nodes.compactMap(\.condition).flatMap { condition -> [String] in
            switch condition {
            case .fileExists(let path), .applicationRunning(let path): [path]
            case .valueEquals(let lhs, let rhs): [lhs, rhs]
            }
        }
        let produced = Set(workflow.nodes.compactMap(\.outputVariable))
        return Set((configured + conditions).flatMap(RecipeVariableResolver.placeholders)).subtracting(produced)
    }

    private func executeWithRetry(node: WorkflowNode, inputs: [String: WorkflowValue],
                                  workflow: WorkflowDefinition) async throws -> WorkflowNodeExecutionResult {
        var lastError: Error?
        for attempt in 0...node.retryCount {
            do { return try await executor.execute(node: node, inputs: inputs, workflow: workflow) }
            catch {
                lastError = error
                guard attempt < node.retryCount, !Task.isCancelled, !isCancellationRequested else { throw error }
            }
        }
        throw lastError ?? CancellationError()
    }

    @discardableResult
    private func rollback(_ operations: [WorkflowUndoOperation]) -> Bool {
        state = .rollingBack
        guard !operations.isEmpty else { return false }
        do {
            for operation in operations.reversed() { try files.undo(operation.fileRecord) }
            return true
        } catch { return false }
    }

    private func finish(_ workflow: WorkflowDefinition, id: UUID, startedAt: Date, succeeded: Bool,
                        rolledBack: Bool, nodes: [WorkflowNodeReceipt], undo: [WorkflowUndoOperation]) -> WorkflowExecutionReceipt {
        let receipt = WorkflowExecutionReceipt(id: id, workflow: workflow, startedAt: startedAt, completedAt: .now,
                                               succeeded: succeeded, wasRolledBack: rolledBack, wasUndone: false,
                                               nodes: nodes, undoOperations: undo)
        receiptStore.save(receipt)
        return receipt
    }

    private func failedReceipt(_ workflow: WorkflowDefinition, message: String) -> WorkflowExecutionReceipt {
        let receipt = WorkflowExecutionReceipt(id: UUID(), workflow: workflow, startedAt: .now, completedAt: .now,
                                               succeeded: false, wasRolledBack: false, wasUndone: false, nodes: [], undoOperations: [])
        receiptStore.save(receipt)
        return receipt
    }
}
