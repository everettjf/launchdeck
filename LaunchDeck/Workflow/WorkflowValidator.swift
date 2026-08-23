import Foundation

nonisolated struct WorkflowValidationIssue: Codable, Hashable, Identifiable, Sendable {
    enum Severity: String, Codable, Hashable, Sendable { case error, warning }
    let id: String
    let severity: Severity
    let message: String
    let nodeID: UUID?
    let portID: String?

    init(_ id: String, _ message: String, severity: Severity = .error,
         nodeID: UUID? = nil, portID: String? = nil) {
        self.id = id
        self.severity = severity
        self.message = message
        self.nodeID = nodeID
        self.portID = portID
    }
}

nonisolated enum WorkflowValidator {
    static let maximumNodes = 1_000

    static func validate(_ workflow: WorkflowDefinition) -> [WorkflowValidationIssue] {
        var issues: [WorkflowValidationIssue] = []
        if workflow.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init("workflow.name", "Workflow name is required."))
        }
        if workflow.schemaVersion != WorkflowDefinition.currentSchemaVersion {
            issues.append(.init("workflow.schema", "Unsupported workflow schema version \(workflow.schemaVersion)."))
        }
        if workflow.nodes.isEmpty { issues.append(.init("workflow.empty", "Add at least one block.")) }
        if workflow.nodes.count > maximumNodes {
            issues.append(.init("workflow.too-large", "A workflow can contain at most \(maximumNodes) blocks."))
        }
        if Set(workflow.nodes.map(\.id)).count != workflow.nodes.count {
            issues.append(.init("workflow.duplicate-node", "Block identifiers must be unique."))
        }
        if Set(workflow.edges.map(\.id)).count != workflow.edges.count {
            issues.append(.init("workflow.duplicate-edge", "Connection identifiers must be unique."))
        }

        let nodes = workflow.nodes.reduce(into: [UUID: WorkflowNode]()) { result, node in
            if result[node.id] == nil { result[node.id] = node }
        }
        var connectedInputs = Set<String>()
        for edge in workflow.edges {
            guard let source = nodes[edge.sourceNodeID] else {
                issues.append(.init("edge.\(edge.id).source", "Connection source no longer exists.")); continue
            }
            guard let target = nodes[edge.targetNodeID] else {
                issues.append(.init("edge.\(edge.id).target", "Connection target no longer exists.")); continue
            }
            guard source.id != target.id else {
                issues.append(.init("edge.\(edge.id).self", "A block cannot connect to itself.", nodeID: source.id)); continue
            }
            guard let sourcePort = WorkflowNodeCatalog.definition(for: source.kindIdentifier)?.outputs.first(where: { $0.id == edge.sourcePortID }) else {
                issues.append(.init("edge.\(edge.id).source-port", "Source port \(edge.sourcePortID) does not exist.", nodeID: source.id, portID: edge.sourcePortID)); continue
            }
            guard let targetPort = WorkflowNodeCatalog.definition(for: target.kindIdentifier)?.inputs.first(where: { $0.id == edge.targetPortID }) else {
                issues.append(.init("edge.\(edge.id).target-port", "Target port \(edge.targetPortID) does not exist.", nodeID: target.id, portID: edge.targetPortID)); continue
            }
            if !targetPort.valueType.accepts(sourcePort.valueType) {
                issues.append(.init("edge.\(edge.id).type", "\(sourcePort.valueType) cannot connect to \(targetPort.valueType).", nodeID: target.id, portID: targetPort.id))
            }
            let key = "\(target.id.uuidString):\(targetPort.id)"
            if !targetPort.allowsMultipleConnections, !connectedInputs.insert(key).inserted {
                issues.append(.init("edge.\(edge.id).multiple", "\(targetPort.name) accepts only one connection.", nodeID: target.id, portID: targetPort.id))
            }
        }

        for node in workflow.nodes {
            guard let definition = WorkflowNodeCatalog.definition(for: node.kindIdentifier) else {
                issues.append(.init("node.\(node.id).unknown", "Unknown block type: \(node.kindIdentifier).", nodeID: node.id)); continue
            }
            for port in definition.inputs where port.isRequired {
                let key = "\(node.id.uuidString):\(port.id)"
                if !connectedInputs.contains(key), node.configuration[port.id] == nil {
                    issues.append(.init("node.\(node.id).\(port.id).required", "\(definition.title) requires \(port.name).", nodeID: node.id, portID: port.id))
                }
            }
            for (key, value) in node.configuration {
                guard let port = definition.inputs.first(where: { $0.id == key }) else { continue }
                if !port.valueType.accepts(value.valueType) {
                    issues.append(.init("node.\(node.id).\(key).configuration", "Configured \(key) is \(value.valueType), expected \(port.valueType).", nodeID: node.id, portID: key))
                }
            }
            if definition.isMutating, !definition.isReversible {
                issues.append(.init("node.\(node.id).irreversible", "\(definition.title) cannot be rolled back automatically.", severity: .warning, nodeID: node.id))
            }
        }

        if topologicalOrder(for: workflow) == nil {
            issues.append(.init("workflow.cycle", "Workflow connections contain a cycle."))
        }
        return issues.sorted { ($0.nodeID?.uuidString ?? "", $0.id) < ($1.nodeID?.uuidString ?? "", $1.id) }
    }

    static func topologicalOrder(for workflow: WorkflowDefinition) -> [UUID]? {
        let IDs = Set(workflow.nodes.map(\.id))
        var incoming = Dictionary(uniqueKeysWithValues: IDs.map { ($0, 0) })
        var outgoing: [UUID: [UUID]] = [:]
        for edge in workflow.edges where IDs.contains(edge.sourceNodeID) && IDs.contains(edge.targetNodeID) {
            incoming[edge.targetNodeID, default: 0] += 1
            outgoing[edge.sourceNodeID, default: []].append(edge.targetNodeID)
        }
        let position = workflow.nodes.enumerated().reduce(into: [UUID: Int]()) { result, pair in
            if result[pair.element.id] == nil { result[pair.element.id] = pair.offset }
        }
        var ready = incoming.filter { $0.value == 0 }.map(\.key).sorted { position[$0, default: 0] < position[$1, default: 0] }
        var result: [UUID] = []
        while !ready.isEmpty {
            let id = ready.removeFirst()
            result.append(id)
            for target in outgoing[id, default: []] {
                incoming[target, default: 0] -= 1
                if incoming[target] == 0 {
                    ready.append(target)
                    ready.sort { position[$0, default: 0] < position[$1, default: 0] }
                }
            }
        }
        return result.count == IDs.count ? result : nil
    }
}

nonisolated enum WorkflowGraphEditor {
    static func connecting(_ edge: WorkflowEdge, in workflow: WorkflowDefinition) -> WorkflowDefinition? {
        var candidate = workflow
        candidate.edges.removeAll { $0.targetNodeID == edge.targetNodeID && $0.targetPortID == edge.targetPortID }
        candidate.edges.append(edge)
        return WorkflowValidator.validate(candidate).contains {
            ($0.severity == .error && $0.id.hasPrefix("edge.\(edge.id)")) || $0.id == "workflow.cycle"
        } ? nil : candidate
    }

    static func automaticLayout(_ workflow: WorkflowDefinition) -> WorkflowDefinition {
        guard let order = WorkflowValidator.topologicalOrder(for: workflow) else { return workflow }
        var result = workflow
        let incoming = Dictionary(grouping: workflow.edges, by: \.targetNodeID)
        var depth: [UUID: Int] = [:]
        for id in order {
            depth[id] = incoming[id, default: []].map { depth[$0.sourceNodeID, default: -1] + 1 }.max() ?? 0
        }
        let groups = Dictionary(grouping: order) { depth[$0, default: 0] }
        let indices = Dictionary(uniqueKeysWithValues: result.nodes.enumerated().map { ($0.element.id, $0.offset) })
        for (level, IDs) in groups {
            for (column, id) in IDs.enumerated() {
                guard let index = indices[id] else { continue }
                result.nodes[index].position = WorkflowPoint(x: Double(column) * 280 + 80, y: Double(level) * 180 + 80)
            }
        }
        return result
    }
}
