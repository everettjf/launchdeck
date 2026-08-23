import Foundation
import LaunchDeckCore

enum IntentActionResolution: Equatable, Sendable {
    case action(LaunchDeckAction)
    case missingParameters([String])
    case unresolved
}

enum IntentActionResolver {
    static func resolve(_ recommendation: IntentRecommendation, target: SearchItem,
                        applicationName: String? = nil, installedApplications: [String: String] = [:],
                        recipes: [Recipe] = [],
                        registry: ActionRegistry = .shared) -> IntentActionResolution {
        var parameters = recommendation.parameters
        switch target.target {
        case .application(let identifier, _):
            parameters["identifier"] = identifier
            parameters["name"] = applicationName ?? target.title
        case .file(let path): parameters["path"] = path
        case .project(let path), .folder(let path):
            parameters["path"] = path
            parameters["directory"] = path
        case .systemSetting(let identifier): parameters["identifier"] = identifier
        case .shortcut(let name): parameters["name"] = name
        case .recipe(let identifier): parameters["identifier"] = identifier.uuidString
        case .registeredAction: break
        }
        if recommendation.actionIdentifier == "open.file-with",
           let identifier = parameters["applicationIdentifier"] {
            guard let trustedName = installedApplications[identifier] else { return .unresolved }
            parameters["applicationName"] = trustedName
        }
        let missing = registry.missingParameters(actionIdentifier: recommendation.actionIdentifier,
                                                 parameters: parameters)
        guard missing.isEmpty else { return .missingParameters(missing) }
        guard let action = registry.resolve(actionIdentifier: recommendation.actionIdentifier,
                                            parameters: parameters, recipes: recipes) else { return .unresolved }
        return .action(action)
    }
}
