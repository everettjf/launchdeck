import Foundation

nonisolated struct RecipeVariable: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var defaultValue: String

    init(id: UUID = UUID(), name: String, defaultValue: String = "") {
        self.id = id
        self.name = name
        self.defaultValue = defaultValue
    }
}

nonisolated enum RecipeVariableResolution: Equatable, Sendable {
    case resolved([RecipeStep])
    case missing([String])
}

nonisolated enum RecipeVariableResolver {
    static func resolve(steps: [RecipeStep], variables: [RecipeVariable], values: [String: String]) -> RecipeVariableResolution {
        let defaults = Dictionary(uniqueKeysWithValues: variables.map { ($0.name, $0.defaultValue) })
        let required = Set(steps.flatMap { placeholders(in: strings(in: $0.operation).joined(separator: " ")) })
        let missing = required.filter { (values[$0] ?? defaults[$0] ?? "").isEmpty }.sorted()
        guard missing.isEmpty else { return .missing(missing) }

        let replacements = defaults.merging(values) { _, supplied in supplied }
        return .resolved(steps.map { step in
            RecipeStep(id: step.id, operation: substitute(step.operation, replacements: replacements))
        })
    }

    static func placeholders(in value: String) -> [String] {
        let pattern = #"\{\{\s*([A-Za-z][A-Za-z0-9_-]{0,63})\s*\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: value) else { return nil }
            return String(value[capture])
        }
    }

    private static func strings(in operation: RecipeStep.Operation) -> [String] {
        switch operation {
        case .openApplication(let identifier, let name): return [identifier, name]
        case .openProject(let path), .openTerminal(let path), .runShortcut(let path): return [path]
        }
    }

    private static func substitute(_ operation: RecipeStep.Operation, replacements: [String: String]) -> RecipeStep.Operation {
        func value(_ source: String) -> String {
            let pattern = #"\{\{\s*([A-Za-z][A-Za-z0-9_-]{0,63})\s*\}\}"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
            var result = source
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).reversed() {
                guard let fullRange = Range(match.range(at: 0), in: result),
                      let keyRange = Range(match.range(at: 1), in: source) else { continue }
                result.replaceSubrange(fullRange, with: replacements[String(source[keyRange])] ?? "")
            }
            return result
        }
        switch operation {
        case .openApplication(let identifier, let name): return .openApplication(identifier: value(identifier), name: value(name))
        case .openProject(let path): return .openProject(path: value(path))
        case .openTerminal(let directory): return .openTerminal(directory: value(directory))
        case .runShortcut(let name): return .runShortcut(name: value(name))
        }
    }
}

nonisolated struct RecipeTemplate: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let summary: String
    let variables: [RecipeVariable]
    let steps: [RecipeStep]
}

nonisolated enum RecipeTemplateCatalog {
    static let templates: [RecipeTemplate] = [
        RecipeTemplate(
            id: "coding-session", name: "Coding Session",
            summary: "Open a project and a Terminal window at the same workspace.",
            variables: [RecipeVariable(name: "projectPath")],
            steps: [.openProject(path: "{{projectPath}}"), .openTerminal(directory: "{{projectPath}}")]
        ),
        RecipeTemplate(
            id: "shortcut-workflow", name: "Shortcut Workflow",
            summary: "Run an explicitly approved Apple Shortcut.",
            variables: [RecipeVariable(name: "shortcutName")],
            steps: [
                .runShortcut(name: "{{shortcutName}}")
            ]
        )
    ]
}

nonisolated enum RecipeStepOrder {
    static func moving(_ steps: [RecipeStep], from source: Int, to destination: Int) -> [RecipeStep] {
        guard steps.indices.contains(source), destination >= 0, destination <= steps.count else { return steps }
        var result = steps
        let step = result.remove(at: source)
        let adjusted = min(destination > source ? destination - 1 : destination, result.count)
        result.insert(step, at: adjusted)
        return result
    }
}
