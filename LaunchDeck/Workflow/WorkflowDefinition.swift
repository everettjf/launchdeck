import Foundation

nonisolated indirect enum WorkflowValueType: Codable, Hashable, Sendable, CustomStringConvertible {
    case control
    case any
    case text
    case number
    case boolean
    case url
    case file
    case folder
    case image
    case application
    case object
    case collection(WorkflowValueType)
    case structured(schemaID: String)

    var description: String {
        switch self {
        case .control: "Control"
        case .any: "Any"
        case .text: "Text"
        case .number: "Number"
        case .boolean: "Boolean"
        case .url: "URL"
        case .file: "File"
        case .folder: "Folder"
        case .image: "Image"
        case .application: "Application"
        case .object: "Object"
        case .collection(let element): "Collection<\(element)>"
        case .structured(let schemaID): schemaID
        }
    }

    func accepts(_ source: WorkflowValueType) -> Bool {
        if self == .any || self == source { return true }
        if self == .object, [.file, .folder, .url, .application, .image, .text].contains(source) { return true }
        if case .collection(let expected) = self, case .collection(let actual) = source {
            return expected.accepts(actual)
        }
        return false
    }
}

nonisolated indirect enum WorkflowValue: Codable, Hashable, Sendable {
    case none
    case text(String)
    case number(Double)
    case boolean(Bool)
    case url(String)
    case file(String)
    case folder(String)
    case image(Data)
    case application(identifier: String, path: String)
    case object(LaunchObject)
    case collection([WorkflowValue])
    case structured([String: WorkflowValue])

    var valueType: WorkflowValueType {
        switch self {
        case .none: .any
        case .text: .text
        case .number: .number
        case .boolean: .boolean
        case .url: .url
        case .file: .file
        case .folder: .folder
        case .image: .image
        case .application: .application
        case .object: .object
        case .collection(let values): .collection(values.first?.valueType ?? .any)
        case .structured: .structured(schemaID: "DynamicObject")
        }
    }

    var stringValue: String? {
        switch self {
        case .text(let value), .url(let value), .file(let value), .folder(let value): value
        case .number(let value): value.formatted()
        case .boolean(let value): value.description
        case .application(let identifier, _): identifier
        case .object(let object): object.value
        case .collection(let values): values.compactMap(\.stringValue).joined(separator: "\n")
        case .structured, .image, .none: nil
        }
    }
}

nonisolated struct WorkflowPoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    static let zero = WorkflowPoint(x: 0, y: 0)
}

nonisolated struct WorkflowPort: Codable, Hashable, Identifiable, Sendable {
    enum Direction: String, Codable, Hashable, Sendable { case input, output }
    let id: String
    var name: String
    var direction: Direction
    var valueType: WorkflowValueType
    var isRequired: Bool
    var allowsMultipleConnections: Bool

    init(_ id: String, name: String, direction: Direction, valueType: WorkflowValueType,
         isRequired: Bool = false, allowsMultipleConnections: Bool = false) {
        self.id = id
        self.name = name
        self.direction = direction
        self.valueType = valueType
        self.isRequired = isRequired
        self.allowsMultipleConnections = allowsMultipleConnections
    }
}

nonisolated struct WorkflowNode: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var kindIdentifier: String
    var title: String
    var configuration: [String: WorkflowValue]
    var position: WorkflowPoint
    var isEnabled: Bool
    var failurePolicy: RecipeStep.FailurePolicy
    var retryCount: Int
    var condition: RecipeStep.Condition?
    var isOptional: Bool
    var outputVariable: String?

    init(id: UUID = UUID(), kindIdentifier: String, title: String? = nil,
         configuration: [String: WorkflowValue] = [:], position: WorkflowPoint = .zero,
         isEnabled: Bool = true, failurePolicy: RecipeStep.FailurePolicy = .stop, retryCount: Int = 0,
         condition: RecipeStep.Condition? = nil, isOptional: Bool = false, outputVariable: String? = nil) {
        self.id = id
        self.kindIdentifier = kindIdentifier
        self.title = title ?? WorkflowNodeCatalog.definition(for: kindIdentifier)?.title ?? kindIdentifier
        self.configuration = configuration
        self.position = position
        self.isEnabled = isEnabled
        self.failurePolicy = failurePolicy
        self.retryCount = max(0, min(retryCount, 5))
        self.condition = condition
        self.isOptional = isOptional
        self.outputVariable = outputVariable
    }

    private enum CodingKeys: String, CodingKey {
        case id, kindIdentifier, title, configuration, position, isEnabled, failurePolicy,
             retryCount, condition, isOptional, outputVariable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kindIdentifier = try container.decode(String.self, forKey: .kindIdentifier)
        title = try container.decode(String.self, forKey: .title)
        configuration = try container.decodeIfPresent([String: WorkflowValue].self, forKey: .configuration) ?? [:]
        position = try container.decodeIfPresent(WorkflowPoint.self, forKey: .position) ?? .zero
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        failurePolicy = try container.decodeIfPresent(RecipeStep.FailurePolicy.self, forKey: .failurePolicy) ?? .stop
        retryCount = max(0, min(try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0, 5))
        condition = try container.decodeIfPresent(RecipeStep.Condition.self, forKey: .condition)
        isOptional = try container.decodeIfPresent(Bool.self, forKey: .isOptional) ?? false
        outputVariable = try container.decodeIfPresent(String.self, forKey: .outputVariable)
    }
}

nonisolated struct WorkflowEdge: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var sourceNodeID: UUID
    var sourcePortID: String
    var targetNodeID: UUID
    var targetPortID: String

    init(id: UUID = UUID(), sourceNodeID: UUID, sourcePortID: String,
         targetNodeID: UUID, targetPortID: String) {
        self.id = id
        self.sourceNodeID = sourceNodeID
        self.sourcePortID = sourcePortID
        self.targetNodeID = targetNodeID
        self.targetPortID = targetPortID
    }
}

nonisolated enum WorkflowModelPolicy: String, CaseIterable, Hashable, Sendable {
    case automatic
    case onDeviceOnly
    case preferOnDevice
    case externalProvider
}

extension WorkflowModelPolicy: Codable {
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = value == "privateCloudCompute" ? .externalProvider : (Self(rawValue: value) ?? .automatic)
    }
    func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(rawValue) }
}

nonisolated enum WorkflowDataPolicy: String, CaseIterable, Hashable, Sendable {
    case localOnly
    case externalProviderAllowed
    case askEveryTime
}

extension WorkflowDataPolicy: Codable {
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = value == "privateCloudAllowed" ? .externalProviderAllowed : (Self(rawValue: value) ?? .localOnly)
    }
    func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(rawValue) }
}

nonisolated struct WorkflowPolicy: Codable, Hashable, Sendable {
    var modelPolicy: WorkflowModelPolicy = .automatic
    var dataPolicy: WorkflowDataPolicy = .localOnly
    var requiresDryRunBeforeMutation = true
    var rollbackOnFailure = true
    var toolAllowlist: Set<String> = []
}

nonisolated struct WorkflowDefinition: Codable, Hashable, Identifiable, Sendable {
    static let currentSchemaVersion = 2
    let id: UUID
    var schemaVersion: Int
    var name: String
    var nodes: [WorkflowNode]
    var edges: [WorkflowEdge]
    var variables: [RecipeVariable]
    var policy: WorkflowPolicy

    init(id: UUID = UUID(), name: String, nodes: [WorkflowNode] = [], edges: [WorkflowEdge] = [],
         variables: [RecipeVariable] = [], policy: WorkflowPolicy = WorkflowPolicy()) {
        self.id = id
        schemaVersion = Self.currentSchemaVersion
        self.name = name
        self.nodes = nodes
        self.edges = edges
        self.variables = variables
        self.policy = policy
    }
}

nonisolated struct WorkflowNodeDefinition: Identifiable, Hashable, Sendable {
    enum Category: String, CaseIterable, Sendable { case input, action, ai, logic, data, output }
    let id: String
    let title: String
    let summary: String
    let systemImage: String
    let category: Category
    let inputs: [WorkflowPort]
    let outputs: [WorkflowPort]
    let isMutating: Bool
    let isReversible: Bool
    let requiredToolIDs: Set<String>
}

nonisolated enum WorkflowNodeCatalog {
    private static let controlIn = WorkflowPort("control", name: "Control", direction: .input, valueType: .control)
    private static let controlOut = WorkflowPort("control", name: "Control", direction: .output, valueType: .control)
    private static let objectsIn = WorkflowPort("objects", name: "Objects", direction: .input, valueType: .collection(.object))
    private static let objectsOut = WorkflowPort("objects", name: "Objects", direction: .output, valueType: .collection(.object))

    static let definitions: [WorkflowNodeDefinition] = [
        .init(id: "input.instant-send", title: "Instant Send", summary: "Use objects captured before LaunchDeck opened.", systemImage: "paperplane", category: .input, inputs: [], outputs: [objectsOut, controlOut], isMutating: false, isReversible: false, requiredToolIDs: []),
        .init(id: "input.files", title: "Files", summary: "Use configured files and folders.", systemImage: "doc.on.doc", category: .input, inputs: [], outputs: [objectsOut, controlOut], isMutating: false, isReversible: false, requiredToolIDs: []),
        .init(id: "input.clipboard", title: "Clipboard", summary: "Use clipboard text, image, or file references.", systemImage: "clipboard", category: .input, inputs: [], outputs: [WorkflowPort("value", name: "Value", direction: .output, valueType: .any), controlOut], isMutating: false, isReversible: false, requiredToolIDs: ["clipboard.read"]),
        .init(id: "action.open", title: "Open", summary: "Open every input object.", systemImage: "arrow.up.forward.app", category: .action, inputs: [controlIn, objectsIn], outputs: [objectsOut, controlOut], isMutating: false, isReversible: false, requiredToolIDs: ["objects.open"]),
        .init(id: "action.open-application", title: "Open Application", summary: "Open an application by bundle identifier.", systemImage: "app", category: .action, inputs: [controlIn], outputs: [controlOut], isMutating: false, isReversible: false, requiredToolIDs: ["applications.open"]),
        .init(id: "action.open-terminal", title: "Open Terminal", summary: "Open Terminal in a configured directory.", systemImage: "terminal", category: .action, inputs: [controlIn], outputs: [controlOut], isMutating: false, isReversible: false, requiredToolIDs: ["terminal.open"]),
        .init(id: "action.run-shortcut", title: "Run Shortcut", summary: "Run an approved Apple Shortcut.", systemImage: "shortcuts", category: .action, inputs: [controlIn], outputs: [controlOut], isMutating: true, isReversible: false, requiredToolIDs: ["shortcuts.run"]),
        .init(id: "action.reveal", title: "Reveal", summary: "Reveal input files in Finder.", systemImage: "finder", category: .action, inputs: [controlIn, objectsIn], outputs: [objectsOut, controlOut], isMutating: false, isReversible: false, requiredToolIDs: ["objects.reveal"]),
        .init(id: "action.paste", title: "Paste", summary: "Paste input text into the active application.", systemImage: "doc.on.clipboard", category: .action, inputs: [controlIn, objectsIn], outputs: [objectsOut, controlOut], isMutating: true, isReversible: false, requiredToolIDs: ["objects.paste"]),
        .init(id: "action.openWith", title: "Open With", summary: "Open input objects with a configured application.", systemImage: "square.and.arrow.up", category: .action, inputs: [controlIn, objectsIn], outputs: [objectsOut, controlOut], isMutating: false, isReversible: false, requiredToolIDs: ["objects.open-with"]),
        .init(id: "action.copy", title: "Copy", summary: "Copy objects to the pasteboard.", systemImage: "doc.on.doc", category: .action, inputs: [controlIn, objectsIn], outputs: [objectsOut, controlOut], isMutating: true, isReversible: false, requiredToolIDs: ["objects.copy"]),
        .init(id: "action.move", title: "Move", summary: "Move files to a target folder.", systemImage: "folder.badge.plus", category: .action, inputs: [controlIn, objectsIn, WorkflowPort("target", name: "Target", direction: .input, valueType: .folder, isRequired: true)], outputs: [objectsOut, controlOut], isMutating: true, isReversible: true, requiredToolIDs: ["files.move"]),
        .init(id: "action.duplicate", title: "Duplicate", summary: "Duplicate files and folders.", systemImage: "plus.square.on.square", category: .action, inputs: [controlIn, objectsIn], outputs: [objectsOut, controlOut], isMutating: true, isReversible: true, requiredToolIDs: ["files.duplicate"]),
        .init(id: "action.compress", title: "Compress", summary: "Create ZIP archives.", systemImage: "archivebox", category: .action, inputs: [controlIn, objectsIn], outputs: [objectsOut, controlOut], isMutating: true, isReversible: true, requiredToolIDs: ["files.compress"]),
        .init(id: "action.trash", title: "Move to Trash", summary: "Move files to Trash with undo data.", systemImage: "trash", category: .action, inputs: [controlIn, objectsIn], outputs: [controlOut], isMutating: true, isReversible: true, requiredToolIDs: ["files.trash"]),
        .init(id: "logic.delay", title: "Delay", summary: "Wait for a configured duration.", systemImage: "clock", category: .logic, inputs: [controlIn], outputs: [controlOut], isMutating: false, isReversible: false, requiredToolIDs: []),
        .init(id: "logic.approval", title: "Ask for Approval", summary: "Pause before external or destructive effects.", systemImage: "hand.raised", category: .logic, inputs: [controlIn], outputs: [controlOut], isMutating: false, isReversible: false, requiredToolIDs: []),
        .init(id: "data.text", title: "Text", summary: "Provide a constant or templated text value.", systemImage: "text.quote", category: .data, inputs: [], outputs: [WorkflowPort("value", name: "Text", direction: .output, valueType: .text), controlOut], isMutating: false, isReversible: false, requiredToolIDs: []),
        .init(id: "data.folder", title: "Folder", summary: "Provide a target folder.", systemImage: "folder", category: .data, inputs: [], outputs: [WorkflowPort("value", name: "Folder", direction: .output, valueType: .folder), controlOut], isMutating: false, isReversible: false, requiredToolIDs: []),
        .init(id: "ai.classify", title: "AI Classify", summary: "Classify input with structured output.", systemImage: "tag", category: .ai, inputs: [controlIn, WorkflowPort("input", name: "Input", direction: .input, valueType: .any, isRequired: true)], outputs: [WorkflowPort("result", name: "Result", direction: .output, valueType: .structured(schemaID: "AIResult")), controlOut], isMutating: false, isReversible: false, requiredToolIDs: []),
        .init(id: "ai.extract", title: "AI Extract", summary: "Extract structured fields.", systemImage: "list.bullet.rectangle", category: .ai, inputs: [controlIn, WorkflowPort("input", name: "Input", direction: .input, valueType: .any, isRequired: true)], outputs: [WorkflowPort("result", name: "Result", direction: .output, valueType: .structured(schemaID: "AIResult")), controlOut], isMutating: false, isReversible: false, requiredToolIDs: []),
        .init(id: "ai.summarize", title: "AI Summarize", summary: "Summarize text or objects.", systemImage: "text.alignleft", category: .ai, inputs: [controlIn, WorkflowPort("input", name: "Input", direction: .input, valueType: .any, isRequired: true)], outputs: [WorkflowPort("result", name: "Result", direction: .output, valueType: .text), controlOut], isMutating: false, isReversible: false, requiredToolIDs: []),
        .init(id: "ai.rewrite", title: "AI Rewrite", summary: "Rewrite text using explicit instructions.", systemImage: "pencil.and.scribble", category: .ai, inputs: [controlIn, WorkflowPort("input", name: "Input", direction: .input, valueType: .text, isRequired: true)], outputs: [WorkflowPort("result", name: "Result", direction: .output, valueType: .text), controlOut], isMutating: false, isReversible: false, requiredToolIDs: []),
        .init(id: "ai.filename", title: "AI Filename", summary: "Generate a safe filename suggestion.", systemImage: "character.cursor.ibeam", category: .ai, inputs: [controlIn, WorkflowPort("input", name: "Input", direction: .input, valueType: .any, isRequired: true)], outputs: [WorkflowPort("result", name: "Filename", direction: .output, valueType: .text), controlOut], isMutating: false, isReversible: false, requiredToolIDs: []),
        .init(id: "output.copy", title: "Copy Result", summary: "Copy an output value.", systemImage: "clipboard", category: .output, inputs: [controlIn, WorkflowPort("value", name: "Value", direction: .input, valueType: .any, isRequired: true)], outputs: [controlOut], isMutating: true, isReversible: false, requiredToolIDs: ["clipboard.write"])
    ]

    static func definition(for identifier: String) -> WorkflowNodeDefinition? {
        definitions.first { $0.id == identifier }
    }
}

nonisolated enum RecipeV1Migrator {
    static func migrate(_ recipe: Recipe) -> WorkflowDefinition {
        var nodes: [WorkflowNode] = []
        var edges: [WorkflowEdge] = []
        for (index, step) in recipe.steps.enumerated() {
            let node = node(for: step, index: index)
            if let previous = nodes.last {
                edges.append(.init(sourceNodeID: previous.id, sourcePortID: "control",
                                   targetNodeID: node.id, targetPortID: "control"))
            }
            nodes.append(node)
        }
        return WorkflowDefinition(id: recipe.id, name: recipe.name, nodes: nodes, edges: edges,
                                  variables: recipe.variables)
    }

    private static func node(for step: RecipeStep, index: Int) -> WorkflowNode {
        let kind: String
        var configuration: [String: WorkflowValue] = [:]
        switch step.operation {
        case .openApplication(let identifier, let name):
            kind = "action.open-application"
            configuration["identifier"] = .text(identifier)
            configuration["name"] = .text(name)
        case .openProject(let path):
            kind = "action.open"; configuration["objects"] = .collection([.folder(path)])
        case .openTerminal(let directory):
            kind = "action.open-terminal"; configuration["directory"] = .folder(directory)
        case .runShortcut(let name):
            kind = "action.run-shortcut"; configuration["shortcut"] = .text(name)
        case .delay(let seconds):
            kind = "logic.delay"; configuration["seconds"] = .number(seconds)
        case .objectAction(let action, let sources, let target):
            kind = "action.\(action.rawValue)"
            configuration["objects"] = .collection(sources.map { .file($0) })
            if let target { configuration["target"] = .folder(target) }
        }
        return WorkflowNode(id: step.id, kindIdentifier: kind, title: step.summary,
                            configuration: configuration,
                            position: WorkflowPoint(x: 120, y: Double(index) * 150),
                            failurePolicy: step.failurePolicy, retryCount: step.retryCount,
                            condition: step.condition, isOptional: step.isOptional,
                            outputVariable: step.outputVariable)
    }
}
