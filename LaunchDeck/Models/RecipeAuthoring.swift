import Foundation

nonisolated struct RecipeVariable: Codable, Hashable, Identifiable, Sendable {
    enum ValueType: String, Codable, CaseIterable, Hashable, Sendable { case text, file, folder, choice }
    let id: UUID
    var name: String
    var defaultValue: String
    var valueType: ValueType
    var choices: [String]

    init(id: UUID = UUID(), name: String, defaultValue: String = "", valueType: ValueType = .text, choices: [String] = []) {
        self.id = id
        self.name = name
        self.defaultValue = defaultValue
        self.valueType = valueType
        self.choices = choices
    }

    private enum CodingKeys: String, CodingKey { case id, name, defaultValue, valueType, choices }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue) ?? ""
        valueType = try container.decodeIfPresent(ValueType.self, forKey: .valueType) ?? .text
        choices = try container.decodeIfPresent([String].self, forKey: .choices) ?? []
    }

    func validationError(for value: String) -> String? {
        guard !value.isEmpty else { return nil }
        switch valueType {
        case .text: return nil
        case .file:
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: value, isDirectory: &directory) && !directory.boolValue ? nil : "\(name) must be an existing file."
        case .folder:
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: value, isDirectory: &directory) && directory.boolValue ? nil : "\(name) must be an existing folder."
        case .choice: return choices.contains(value) ? nil : "\(name) must be one of: \(choices.joined(separator: ", "))."
        }
    }
}

nonisolated enum RecipeVariableResolution: Equatable, Sendable {
    case resolved([RecipeStep])
    case missing([String])
    case invalid([String])
}

nonisolated enum RecipeVariableResolver {
    static func resolve(steps: [RecipeStep], variables: [RecipeVariable], values: [String: String]) -> RecipeVariableResolution {
        let defaults = Dictionary(uniqueKeysWithValues: variables.map { ($0.name, $0.defaultValue) })
        let outputNames = Set(steps.compactMap(\.outputVariable))
        let required = Set(steps.flatMap { placeholders(in: strings(in: $0.operation).joined(separator: " ")) })
            .subtracting(outputNames)
        let missing = required.filter { (values[$0] ?? defaults[$0] ?? "").isEmpty }.sorted()
        guard missing.isEmpty else { return .missing(missing) }

        let replacements = defaults.merging(values) { _, supplied in supplied }
        let errors = variables.compactMap { $0.validationError(for: replacements[$0.name, default: ""]) }
        guard errors.isEmpty else { return .invalid(errors) }
        return .resolved(steps.map { substitute($0, replacements: replacements) })
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
        case .delay: return []
        }
    }

    static func substitute(_ step: RecipeStep, replacements: [String: String]) -> RecipeStep {
        let condition: RecipeStep.Condition?
        switch step.condition {
        case .fileExists(let path): condition = .fileExists(path: substitute(path, replacements: replacements))
        case .applicationRunning(let identifier): condition = .applicationRunning(identifier: substitute(identifier, replacements: replacements))
        case .valueEquals(let lhs, let rhs):
            condition = .valueEquals(lhs: substitute(lhs, replacements: replacements), rhs: substitute(rhs, replacements: replacements))
        case nil: condition = nil
        }
        return RecipeStep(id: step.id,
                          operation: substitute(step.operation, replacements: replacements),
                          failurePolicy: step.failurePolicy,
                          condition: condition,
                          retryCount: step.retryCount,
                          isOptional: step.isOptional,
                          outputVariable: step.outputVariable)
    }

    private static func substitute(_ operation: RecipeStep.Operation, replacements: [String: String]) -> RecipeStep.Operation {
        func value(_ source: String) -> String { substitute(source, replacements: replacements) }
        switch operation {
        case .openApplication(let identifier, let name): return .openApplication(identifier: value(identifier), name: value(name))
        case .openProject(let path): return .openProject(path: value(path))
        case .openTerminal(let directory): return .openTerminal(directory: value(directory))
        case .runShortcut(let name): return .runShortcut(name: value(name))
        case .delay(let seconds): return .delay(seconds: seconds)
        }
    }

    private static func substitute(_ source: String, replacements: [String: String]) -> String {
            let pattern = #"\{\{\s*([A-Za-z][A-Za-z0-9_-]{0,63})\s*\}\}"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
            var result = source
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).reversed() {
                guard let fullRange = Range(match.range(at: 0), in: result),
                      let keyRange = Range(match.range(at: 1), in: source) else { continue }
                guard let replacement = replacements[String(source[keyRange])] else { continue }
                result.replaceSubrange(fullRange, with: replacement)
            }
            return result
    }
}

nonisolated struct RecipeDryRunReport: Equatable, Sendable {
    let steps: [String]
    let permissions: [String]
    let errors: [String]
    var isReady: Bool { errors.isEmpty }
}

@MainActor enum RecipeDryRun {
    static func inspect(_ recipe: Recipe, values: [String: String], approvedShortcuts: Set<String>) -> RecipeDryRunReport {
        switch RecipeVariableResolver.resolve(steps: recipe.steps, variables: recipe.variables, values: values) {
        case .missing(let names): return .init(steps: [], permissions: [], errors: ["Missing: \(names.joined(separator: ", "))"])
        case .invalid(let errors): return .init(steps: [], permissions: [], errors: errors)
        case .resolved(let steps):
            let errors = steps.compactMap { ActionPolicy.validate($0.action, approvedShortcuts: approvedShortcuts) }
            let permissions = steps.compactMap { step -> String? in
                switch step.operation {
                case .runShortcut: "Runs an approved Apple Shortcut"
                case .openTerminal: "Opens Terminal"
                case .delay: nil
                default: nil
                }
            }
            return .init(steps: steps.map(\.summary), permissions: Array(Set(permissions)).sorted(), errors: errors)
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
        ),
        RecipeTemplate(id: "writing-session", name: "Writing Session", summary: "Open a writing folder and pause before the next step.",
                       variables: [RecipeVariable(name: "writingFolder", valueType: .folder)],
                       steps: [.openProject(path: "{{writingFolder}}"), .delay(seconds: 1)]),
        RecipeTemplate(id: "meeting-prep", name: "Meeting Preparation", summary: "Open the meeting folder and run an approved preparation Shortcut.",
                       variables: [RecipeVariable(name: "meetingFolder", valueType: .folder), RecipeVariable(name: "prepShortcut")],
                       steps: [.openProject(path: "{{meetingFolder}}"), .runShortcut(name: "{{prepShortcut}}")]),
        RecipeTemplate(id: "image-processing", name: "Image Processing", summary: "Open an image workspace and run an approved processing Shortcut.",
                       variables: [RecipeVariable(name: "imageFolder", valueType: .folder), RecipeVariable(name: "imageShortcut")],
                       steps: [.openProject(path: "{{imageFolder}}"), .runShortcut(name: "{{imageShortcut}}")]),
        RecipeTemplate(id: "project-archive", name: "Project Archive", summary: "Open a project and run an approved archive Shortcut.",
                       variables: [RecipeVariable(name: "projectPath", valueType: .folder), RecipeVariable(name: "archiveShortcut")],
                       steps: [.openProject(path: "{{projectPath}}"), .runShortcut(name: "{{archiveShortcut}}")]),
        RecipeTemplate(id: "daily-shutdown", name: "Daily Shutdown", summary: "Run an approved end-of-day Shortcut.",
                       variables: [RecipeVariable(name: "shutdownShortcut")], steps: [.runShortcut(name: "{{shutdownShortcut}}")]),
        RecipeTemplate(id: "review-build", name: "Review Build", summary: "Open a project, wait for it to settle, then run a build Shortcut.",
                       variables: [RecipeVariable(name: "projectPath", valueType: .folder), RecipeVariable(name: "buildShortcut")],
                       steps: [.openProject(path: "{{projectPath}}"), .delay(seconds: 2), .runShortcut(name: "{{buildShortcut}}")]),
        RecipeTemplate(id: "terminal-workspace", name: "Terminal Workspace", summary: "Open a folder and Terminal in the same location.",
                       variables: [RecipeVariable(name: "workspace", valueType: .folder)],
                       steps: [.openProject(path: "{{workspace}}"), .openTerminal(directory: "{{workspace}}")]),
        RecipeTemplate(id: "research-session", name: "Research Session", summary: "Open a research folder and an approved capture Shortcut.",
                       variables: [RecipeVariable(name: "researchFolder", valueType: .folder), RecipeVariable(name: "captureShortcut")],
                       steps: [.openProject(path: "{{researchFolder}}"), .runShortcut(name: "{{captureShortcut}}")]),
        RecipeTemplate(id: "conditional-project", name: "Conditional Project", summary: "Open a project only when its path exists.",
                       variables: [RecipeVariable(name: "projectPath", valueType: .folder)],
                       steps: [RecipeStep(operation: .openProject(path: "{{projectPath}}"),
                                          condition: .fileExists(path: "{{projectPath}}"), isOptional: true)])
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
