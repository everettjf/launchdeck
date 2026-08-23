import Foundation

nonisolated struct RecipeStep: Codable, Hashable, Identifiable, Sendable {
    enum FailurePolicy: String, Codable, CaseIterable, Hashable, Sendable { case stop, continueNext }
    enum Operation: Codable, Hashable, Sendable {
        case openApplication(identifier: String, name: String)
        case openProject(path: String)
        case openTerminal(directory: String)
        case runShortcut(name: String)
    }

    let id: UUID
    var operation: Operation
    var failurePolicy: FailurePolicy

    init(id: UUID = UUID(), operation: Operation, failurePolicy: FailurePolicy = .stop) {
        self.id = id
        self.operation = operation
        self.failurePolicy = failurePolicy
    }

    private enum CodingKeys: String, CodingKey { case id, operation, failurePolicy }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        operation = try container.decode(Operation.self, forKey: .operation)
        failurePolicy = try container.decodeIfPresent(FailurePolicy.self, forKey: .failurePolicy) ?? .stop
    }

    static func openApplication(identifier: String, name: String) -> Self {
        .init(operation: .openApplication(identifier: identifier, name: name))
    }
    static func openProject(path: String) -> Self { .init(operation: .openProject(path: path)) }
    static func openTerminal(directory: String) -> Self { .init(operation: .openTerminal(directory: directory)) }
    static func runShortcut(name: String) -> Self { .init(operation: .runShortcut(name: name)) }

    var summary: String {
        switch operation {
        case .openApplication(_, let name): return "Open \(name)"
        case .openProject(let path): return "Open project \(URL(fileURLWithPath: path).lastPathComponent)"
        case .openTerminal(let path): return "Open Terminal at \(path)"
        case .runShortcut(let name): return "Run Shortcut “\(name)”"
        }
    }

    var action: LaunchDeckAction {
        switch operation {
        case .openApplication(let id, let name): return .openApplication(identifier: id, name: name)
        case .openProject(let path): return .openProject(path: path)
        case .openTerminal(let directory): return .openTerminal(directory: directory)
        case .runShortcut(let name): return .runShortcut(name: name)
        }
    }
}

nonisolated struct Recipe: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var variables: [RecipeVariable]
    var steps: [RecipeStep]

    init(id: UUID = UUID(), name: String, variables: [RecipeVariable] = [], steps: [RecipeStep]) {
        self.id = id
        self.name = name
        self.variables = variables
        self.steps = steps
    }

    private enum CodingKeys: String, CodingKey { case id, name, variables, steps }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        variables = try container.decodeIfPresent([RecipeVariable].self, forKey: .variables) ?? []
        steps = try container.decode([RecipeStep].self, forKey: .steps)
    }
}

nonisolated enum RecipeValidation {
    static let maximumSteps = 50

    static func error(for recipe: Recipe) -> String? {
        if recipe.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Recipe name is required." }
        if recipe.steps.isEmpty { return "A recipe must contain at least one step." }
        if recipe.steps.count > maximumSteps { return "A recipe can contain at most \(maximumSteps) steps." }
        if Set(recipe.steps.map(\.id)).count != recipe.steps.count { return "Recipe step identifiers must be unique." }
        let names = recipe.variables.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        if names.contains(where: \.isEmpty) { return "Recipe variable names are required." }
        if Set(names).count != names.count { return "Recipe variable names must be unique." }
        if names.contains(where: { RecipeVariableResolver.placeholders(in: "{{\($0)}}").first != $0 }) {
            return "Recipe variable names must begin with a letter and contain only letters, numbers, hyphens, or underscores."
        }
        let placeholders = Set(recipe.steps.flatMap { step -> [String] in
            switch step.operation {
            case .openApplication(let identifier, let name):
                return RecipeVariableResolver.placeholders(in: identifier) + RecipeVariableResolver.placeholders(in: name)
            case .openProject(let path), .openTerminal(let path), .runShortcut(let path):
                return RecipeVariableResolver.placeholders(in: path)
            }
        })
        let undeclared = placeholders.subtracting(names).sorted()
        if !undeclared.isEmpty { return "Declare recipe variables: \(undeclared.joined(separator: ", "))." }
        return nil
    }
}
