import AppKit
import Combine
import Foundation

nonisolated enum WorkflowModelRoute: String, Hashable, Sendable {
    case deterministic
    case onDevice
    case externalProvider
}

extension WorkflowModelRoute: Codable {
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = value == "privateCloudCompute" ? .externalProvider : (Self(rawValue: value) ?? .deterministic)
    }
    func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(rawValue) }
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
        // A newer run may have replaced this one; keep its task so Cancel still reaches it.
        if activeTask == task { activeTask = nil }
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
        let nodes = Dictionary(workflow.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var runtimeVariables = Dictionary(workflow.variables.map { ($0.name, $0.defaultValue) }, uniquingKeysWith: { first, _ in first })
        // Model output is untrusted: track where it flows so it cannot silently become a path or URL.
        var aiDerivedVariables = Set<String>()
        var aiDerivedNodeIDs = Set<UUID>()
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
            if let violation = AIDerivedValueGuard.variableViolation(in: storedNode, variables: runtimeVariables,
                                                                     aiDerived: aiDerivedVariables) {
                nodeReceipts.append(.init(id: UUID(), nodeID: storedNode.id, title: storedNode.title, startedAt: .now,
                                          duration: 0, outcome: "failed", route: .deterministic,
                                          outputTypes: [:], error: violation))
                let rolledBack = workflow.policy.rollbackOnFailure && rollback(undo)
                state = .failed(violation)
                return finish(workflow, id: receiptID, startedAt: startedAt, succeeded: false,
                              rolledBack: rolledBack, nodes: nodeReceipts, undo: undo)
            }
            let node = resolved(node: storedNode, variables: runtimeVariables, aiDerived: aiDerivedVariables)
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
                if WorkflowNodeCatalog.definition(for: node.kindIdentifier)?.isMutating == true {
                    try AIDerivedValueGuard.checkMutatingInputs(of: node, workflow: workflow, outputs: outputs,
                                                                aiDerivedNodeIDs: aiDerivedNodeIDs)
                }
                let result = try await executeWithRetry(node: node, inputs: inputs, workflow: workflow)
                outputs[nodeID] = result.outputs
                let isAIDerived = result.route != .deterministic
                    || workflow.edges.contains { $0.targetNodeID == nodeID && aiDerivedNodeIDs.contains($0.sourceNodeID) }
                if isAIDerived { aiDerivedNodeIDs.insert(nodeID) }
                if let outputVariable = node.outputVariable,
                   let value = result.outputs.keys.sorted().filter({ $0 != "control" }).compactMap({ result.outputs[$0]?.stringValue }).first {
                    runtimeVariables[outputVariable] = value
                    if isAIDerived { aiDerivedVariables.insert(outputVariable) } else { aiDerivedVariables.remove(outputVariable) }
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

    private func resolved(node: WorkflowNode, variables: [String: String], aiDerived: Set<String> = []) -> WorkflowNode {
        var result = node
        // Model output placed in a URL is percent-encoded so it cannot add a scheme, host or query.
        var urlVariables = variables
        for name in aiDerived { urlVariables[name] = variables[name].map(AIDerivedValueGuard.encodedForURL) }
        result.configuration = node.configuration.mapValues { value in
            if case .url(let raw) = value { return .url(RecipeVariableResolver.substitute(raw, replacements: urlVariables)) }
            return substitute(value, variables: variables)
        }
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

/// Keeps model output from steering file operations. Output substituted into a file or folder
/// field must be a single plain name, and output wired into a mutating action must be an
/// existing absolute path with no `..` segments.
nonisolated enum AIDerivedValueGuard {
    static func isSafePathComponent(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 255 && value != "." && value != ".." && !value.hasPrefix("~")
            && !value.contains(where: { $0 == "/" || $0 == ":" || $0.isNewline || $0 == "\0" })
    }

    static func isSafeExistingPath(_ value: String) -> Bool {
        guard value.hasPrefix("/"), !value.contains(where: { $0.isNewline || $0 == "\0" }),
              !value.split(separator: "/").contains("..") else { return false }
        return FileManager.default.fileExists(atPath: value)
    }

    static func encodedForURL(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? ""
    }

    static func variableViolation(in node: WorkflowNode, variables: [String: String], aiDerived: Set<String>) -> String? {
        guard !aiDerived.isEmpty else { return nil }
        func pathTemplates(_ value: WorkflowValue) -> [String] {
            switch value {
            case .file(let path), .folder(let path): [path]
            case .application(_, let path): [path]
            case .object(let object) where [.file, .folder].contains(object.kind): [object.value]
            case .collection(let values): values.flatMap(pathTemplates)
            case .structured(let values): values.values.flatMap(pathTemplates)
            default: []
            }
        }
        let templates = node.configuration.values.flatMap(pathTemplates)
        for name in aiDerived.sorted() {
            guard templates.contains(where: { references($0, variable: name) }),
                  let value = variables[name], !isSafePathComponent(value) else { continue }
            return "AI output “\(name)” cannot be used in a file path because it is not a plain file name."
        }
        return nil
    }

    static func checkMutatingInputs(of node: WorkflowNode, workflow: WorkflowDefinition,
                                    outputs: [UUID: [String: WorkflowValue]], aiDerivedNodeIDs: Set<UUID>) throws {
        for edge in workflow.edges where edge.targetNodeID == node.id && aiDerivedNodeIDs.contains(edge.sourceNodeID) {
            guard edge.targetPortID != "control", let value = outputs[edge.sourceNodeID]?[edge.sourcePortID] else { continue }
            for path in paths(in: value) where !isSafeExistingPath(path) {
                throw WorkflowAISafetyError(port: edge.targetPortID, value: String(path.prefix(80)))
            }
        }
    }

    private static func paths(in value: WorkflowValue) -> [String] {
        switch value {
        case .text(let path), .file(let path), .folder(let path), .url(let path): [path]
        case .application(_, let path): [path]
        case .object(let object): [object.value]
        case .collection(let values): values.flatMap(paths)
        case .structured(let values): values.values.flatMap(paths)
        default: []
        }
    }

    private static func references(_ template: String, variable: String) -> Bool {
        RecipeVariableResolver.substitute(template, replacements: [variable: "\u{1}"]) != template
    }
}

nonisolated struct WorkflowAISafetyError: LocalizedError {
    let port: String
    let value: String
    var errorDescription: String? {
        "AI output for “\(port)” must be an existing absolute path before a file action can use it (got “\(value)”)."
    }
}
