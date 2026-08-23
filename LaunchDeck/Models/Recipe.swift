import Foundation

nonisolated struct RecipeStep: Codable, Hashable, Identifiable, Sendable {
    enum ObjectActionKind: String, Codable, Hashable, Sendable {
        case open, reveal, copy, paste, openWith, move, duplicate, compress, trash
    }
    enum FailurePolicy: String, Codable, CaseIterable, Hashable, Sendable { case stop, continueNext }
    enum Condition: Codable, Hashable, Sendable {
        case fileExists(path: String)
        case applicationRunning(identifier: String)
        case valueEquals(lhs: String, rhs: String)
    }
    enum Operation: Codable, Hashable, Sendable {
        case openApplication(identifier: String, name: String)
        case openProject(path: String)
        case openTerminal(directory: String)
        case runShortcut(name: String)
        case delay(seconds: Double)
        case objectAction(kind: ObjectActionKind, sources: [String], target: String?)
    }

    let id: UUID
    var operation: Operation
    var failurePolicy: FailurePolicy
    var condition: Condition?
    var retryCount: Int
    var isOptional: Bool
    var outputVariable: String?

    init(id: UUID = UUID(), operation: Operation, failurePolicy: FailurePolicy = .stop,
         condition: Condition? = nil, retryCount: Int = 0, isOptional: Bool = false,
         outputVariable: String? = nil) {
        self.id = id
        self.operation = operation
        self.failurePolicy = failurePolicy
        self.condition = condition
        self.retryCount = max(0, min(retryCount, 5))
        self.isOptional = isOptional
        self.outputVariable = outputVariable
    }

    private enum CodingKeys: String, CodingKey {
        case id, operation, failurePolicy, condition, retryCount, isOptional, outputVariable
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        operation = try container.decode(Operation.self, forKey: .operation)
        failurePolicy = try container.decodeIfPresent(FailurePolicy.self, forKey: .failurePolicy) ?? .stop
        condition = try container.decodeIfPresent(Condition.self, forKey: .condition)
        retryCount = max(0, min(try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0, 5))
        isOptional = try container.decodeIfPresent(Bool.self, forKey: .isOptional) ?? false
        outputVariable = try container.decodeIfPresent(String.self, forKey: .outputVariable)
    }

    static func openApplication(identifier: String, name: String) -> Self {
        .init(operation: .openApplication(identifier: identifier, name: name))
    }
    static func openProject(path: String) -> Self { .init(operation: .openProject(path: path)) }
    static func openTerminal(directory: String) -> Self { .init(operation: .openTerminal(directory: directory)) }
    static func runShortcut(name: String) -> Self { .init(operation: .runShortcut(name: name)) }
    static func delay(seconds: Double) -> Self { .init(operation: .delay(seconds: seconds)) }
    static func objectAction(_ kind: ObjectActionKind, sources: [String], target: String? = nil) -> Self {
        .init(operation: .objectAction(kind: kind, sources: sources, target: target))
    }

    var summary: String {
        switch operation {
        case .openApplication(_, let name): return "Open \(name)"
        case .openProject(let path): return "Open project \(URL(fileURLWithPath: path).lastPathComponent)"
        case .openTerminal(let path): return "Open Terminal at \(path)"
        case .runShortcut(let name): return "Run Shortcut “\(name)”"
        case .delay(let seconds): return "Wait \(seconds.formatted()) seconds"
        case .objectAction(let kind, let sources, let target):
            return "\(kind.rawValue.capitalized) \(sources.count) item\(sources.count == 1 ? "" : "s")\(target.map { " → \($0)" } ?? "")"
        }
    }

    var action: LaunchDeckAction {
        switch operation {
        case .openApplication(let id, let name): return .openApplication(identifier: id, name: name)
        case .openProject(let path): return .openProject(path: path)
        case .openTerminal(let directory): return .openTerminal(directory: directory)
        case .runShortcut(let name): return .runShortcut(name: name)
        case .delay(let seconds): return .wait(seconds: seconds)
        case .objectAction(let kind, let sources, let target): return .objectAction(kind: kind, sources: sources, target: target)
        }
    }
}

nonisolated struct Recipe: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var variables: [RecipeVariable]
    var steps: [RecipeStep]
    var schemaVersion: Int
    var workflow: WorkflowDefinition?

    init(id: UUID = UUID(), name: String, variables: [RecipeVariable] = [], steps: [RecipeStep]) {
        self.id = id
        self.name = name
        self.variables = variables
        self.steps = steps
        schemaVersion = 1
        workflow = nil
    }

    init(workflow: WorkflowDefinition) {
        id = workflow.id
        name = workflow.name
        variables = workflow.variables
        steps = []
        schemaVersion = WorkflowDefinition.currentSchemaVersion
        self.workflow = workflow
    }

    private enum CodingKeys: String, CodingKey { case id, name, variables, steps, schemaVersion, workflow }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        variables = try container.decodeIfPresent([RecipeVariable].self, forKey: .variables) ?? []
        steps = try container.decodeIfPresent([RecipeStep].self, forKey: .steps) ?? []
        workflow = try container.decodeIfPresent(WorkflowDefinition.self, forKey: .workflow)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? (workflow == nil ? 1 : 2)
    }
    var resolvedWorkflow: WorkflowDefinition { workflow ?? RecipeV1Migrator.migrate(self) }
}

nonisolated enum RecipeValidation {
    static let maximumSteps = 50

    static func error(for recipe: Recipe) -> String? {
        if recipe.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Recipe name is required." }
        if recipe.steps.isEmpty, recipe.workflow == nil { return "A recipe must contain at least one step or workflow node." }
        if let workflow = recipe.workflow,
           let issue = WorkflowValidator.validate(workflow).first(where: { $0.severity == .error }) {
            return issue.message
        }
        if recipe.steps.count > maximumSteps { return "A recipe can contain at most \(maximumSteps) steps." }
        if Set(recipe.steps.map(\.id)).count != recipe.steps.count { return "Recipe step identifiers must be unique." }
        if recipe.steps.contains(where: { $0.retryCount < 0 || $0.retryCount > 5 }) { return "Recipe retry counts must be between 0 and 5." }
        let names = recipe.variables.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        if names.contains(where: \.isEmpty) { return "Recipe variable names are required." }
        if Set(names).count != names.count { return "Recipe variable names must be unique." }
        if names.contains(where: { RecipeVariableResolver.placeholders(in: "{{\($0)}}").first != $0 }) {
            return "Recipe variable names must begin with a letter and contain only letters, numbers, hyphens, or underscores."
        }
        let outputNames = recipe.steps.compactMap(\.outputVariable)
        if outputNames.contains(where: { RecipeVariableResolver.placeholders(in: "{{\($0)}}").first != $0 }) {
            return "Output variable names must use the same format as recipe variables."
        }
        if Set(outputNames).count != outputNames.count { return "Output variable names must be unique." }
        let placeholders = Set(recipe.steps.flatMap { step -> [String] in
            switch step.operation {
            case .openApplication(let identifier, let name):
                return RecipeVariableResolver.placeholders(in: identifier) + RecipeVariableResolver.placeholders(in: name)
            case .openProject(let path), .openTerminal(let path), .runShortcut(let path):
                return RecipeVariableResolver.placeholders(in: path)
            case .delay: return []
            case .objectAction(_, let sources, let target):
                return sources.flatMap(RecipeVariableResolver.placeholders)
                    + (target.map(RecipeVariableResolver.placeholders) ?? [])
            }
        })
        let undeclared = placeholders.subtracting(Set(names + outputNames)).sorted()
        if !undeclared.isEmpty { return "Declare recipe variables: \(undeclared.joined(separator: ", "))." }
        return nil
    }
}
