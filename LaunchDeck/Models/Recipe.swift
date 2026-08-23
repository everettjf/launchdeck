import Foundation

struct RecipeStep: Codable, Hashable, Identifiable, Sendable {
    enum Operation: Codable, Hashable, Sendable {
        case openApplication(identifier: String, name: String)
        case openProject(path: String)
        case openTerminal(directory: String)
        case runShortcut(name: String)
    }

    let id: UUID
    var operation: Operation

    init(id: UUID = UUID(), operation: Operation) {
        self.id = id
        self.operation = operation
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

struct Recipe: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var steps: [RecipeStep]

    init(id: UUID = UUID(), name: String, steps: [RecipeStep]) {
        self.id = id
        self.name = name
        self.steps = steps
    }
}

enum RecipeValidation {
    static let maximumSteps = 50

    static func error(for recipe: Recipe) -> String? {
        if recipe.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Recipe name is required." }
        if recipe.steps.isEmpty { return "A recipe must contain at least one step." }
        if recipe.steps.count > maximumSteps { return "A recipe can contain at most \(maximumSteps) steps." }
        if Set(recipe.steps.map(\.id)).count != recipe.steps.count { return "Recipe step identifiers must be unique." }
        return nil
    }
}
