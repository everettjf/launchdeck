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
    let outputTypes: [String: WorkflowValueType]
    let error: String?
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

    init(executor: any WorkflowNodeExecuting, receiptStore: WorkflowReceiptStore,
         files: FileOperationService = FileOperationService()) {
        self.executor = executor
        self.receiptStore = receiptStore
        self.files = files
    }

    func dryRun(_ workflow: WorkflowDefinition) -> [WorkflowValidationIssue] {
        WorkflowValidator.validate(workflow)
    }

    func run(_ workflow: WorkflowDefinition) async -> WorkflowExecutionReceipt {
        isCancellationRequested = false
        state = .validating
        let errors = WorkflowValidator.validate(workflow).filter { $0.severity == .error }
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

        for nodeID in order {
            if Task.isCancelled || isCancellationRequested {
                if workflow.policy.rollbackOnFailure { rollback(undo) }
                state = .cancelled
                return finish(workflow, id: receiptID, startedAt: startedAt, succeeded: false,
                              rolledBack: workflow.policy.rollbackOnFailure, nodes: nodeReceipts, undo: undo)
            }
            guard let node = nodes[nodeID], node.isEnabled else { continue }
            guard RecipeRunner.conditionMatches(node.condition) else {
                nodeReceipts.append(.init(id: UUID(), nodeID: node.id, title: node.title, startedAt: .now,
                                          duration: 0, outcome: "skipped", route: .deterministic,
                                          outputTypes: [:], error: nil))
                continue
            }
            activeNodeID = nodeID
            let nodeStartedAt = Date()
            do {
                let inputs = resolvedInputs(for: node, workflow: workflow, outputs: outputs)
                let result = try await executeWithRetry(node: node, inputs: inputs, workflow: workflow)
                outputs[nodeID] = result.outputs
                if let operation = result.undoOperation { undo.append(operation) }
                nodeReceipts.append(.init(id: UUID(), nodeID: node.id, title: node.title, startedAt: nodeStartedAt,
                                          duration: Date().timeIntervalSince(nodeStartedAt), outcome: "succeeded",
                                          route: result.route, outputTypes: result.outputs.mapValues(\.valueType), error: nil))
            } catch {
                nodeReceipts.append(.init(id: UUID(), nodeID: node.id, title: node.title, startedAt: nodeStartedAt,
                                          duration: Date().timeIntervalSince(nodeStartedAt), outcome: "failed",
                                          route: .deterministic, outputTypes: [:], error: error.localizedDescription))
                if node.failurePolicy == .continueNext || node.isOptional { continue }
                if workflow.policy.rollbackOnFailure { rollback(undo) }
                state = .failed(error.localizedDescription)
                return finish(workflow, id: receiptID, startedAt: startedAt, succeeded: false,
                              rolledBack: workflow.policy.rollbackOnFailure, nodes: nodeReceipts, undo: undo)
            }
        }
        activeNodeID = nil
        let receipt = finish(workflow, id: receiptID, startedAt: startedAt, succeeded: true,
                             rolledBack: false, nodes: nodeReceipts, undo: undo)
        state = .completed(receipt.id)
        return receipt
    }

    func cancel() { isCancellationRequested = true }

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

    private func rollback(_ operations: [WorkflowUndoOperation]) {
        state = .rollingBack
        for operation in operations.reversed() { try? files.undo(operation.fileRecord) }
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
