import Foundation

nonisolated struct ActionDescriptor: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let requiredParameters: Set<String>
    let requiresConfirmation: Bool
}

nonisolated struct ActionRegistry: Sendable {
    static let shared = ActionRegistry()
    let descriptors: [ActionDescriptor] = [
        .init(id: "open.application", title: "Open Application", requiredParameters: ["identifier", "name"], requiresConfirmation: false),
        .init(id: "open.file", title: "Open File", requiredParameters: ["path"], requiresConfirmation: false),
        .init(id: "open.file-with", title: "Open File With Application", requiredParameters: ["path", "applicationIdentifier", "applicationName"], requiresConfirmation: false),
        .init(id: "reveal.finder", title: "Reveal in Finder", requiredParameters: ["identifier", "name"], requiresConfirmation: false),
        .init(id: "open.project", title: "Open Project", requiredParameters: ["path"], requiresConfirmation: false),
        .init(id: "run.shortcut", title: "Run Approved Shortcut", requiredParameters: ["name"], requiresConfirmation: true),
        .init(id: "open.terminal", title: "Open Terminal Here", requiredParameters: ["directory"], requiresConfirmation: true),
        .init(id: "run.recipe", title: "Run Recipe", requiredParameters: ["identifier"], requiresConfirmation: true),
        .init(id: "open.settings", title: "Open System Settings", requiredParameters: ["identifier"], requiresConfirmation: false),
    ]

    var identifiers: Set<String> { Set(descriptors.map(\.id)) }

    func missingParameters(actionIdentifier: String, parameters: [String: String]) -> [String] {
        guard let descriptor = descriptors.first(where: { $0.id == actionIdentifier }) else { return ["unknownAction"] }
        return descriptor.requiredParameters.filter { parameters[$0]?.isEmpty != false }.sorted()
    }

    func resolve(actionIdentifier: String, parameters: [String: String], recipes: [Recipe] = []) -> LaunchDeckAction? {
        guard missingParameters(actionIdentifier: actionIdentifier, parameters: parameters).isEmpty else { return nil }
        switch actionIdentifier {
        case "open.application": return .openApplication(identifier: parameters["identifier"]!, name: parameters["name"]!)
        case "open.file": return .openFile(path: parameters["path"]!, applicationIdentifier: nil, applicationName: nil)
        case "open.file-with": return .openFile(path: parameters["path"]!, applicationIdentifier: parameters["applicationIdentifier"], applicationName: parameters["applicationName"])
        case "reveal.finder": return .revealApplication(identifier: parameters["identifier"]!, name: parameters["name"]!)
        case "open.project": return .openProject(path: parameters["path"]!)
        case "run.shortcut": return .runShortcut(name: parameters["name"]!)
        case "open.terminal": return .openTerminal(directory: parameters["directory"]!)
        case "run.recipe":
            guard let id = UUID(uuidString: parameters["identifier"]!), let recipe = recipes.first(where: { $0.id == id }) else { return nil }
            return .runRecipe(identifier: recipe.id, name: recipe.name, steps: recipe.steps)
        case "open.settings":
            guard let destination = SystemSettingsDestination(rawValue: parameters["identifier"]!) else { return nil }
            return .openSystemSettings(destination: destination)
        default: return nil
        }
    }
}
