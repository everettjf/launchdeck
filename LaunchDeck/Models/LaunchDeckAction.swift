import Foundation

enum LaunchDeckAction: Identifiable, Hashable, Sendable {
    case openApplication(identifier: String, name: String)
    case revealApplication(identifier: String, name: String)
    case openURL(URL)
    case openSystemSettings(destination: SystemSettingsDestination)
    case runShortcut(name: String)
    case openFile(path: String, applicationIdentifier: String?, applicationName: String?)
    case openProject(path: String)
    case openTerminal(directory: String)
    case runRecipe(identifier: UUID, name: String, steps: [RecipeStep])
    case wait(seconds: Double)

    var id: String {
        switch self {
        case .openApplication(let identifier, _): return "open-app:\(identifier)"
        case .revealApplication(let identifier, _): return "reveal-app:\(identifier)"
        case .openURL(let url): return "open-url:\(url.absoluteString)"
        case .openSystemSettings(let destination): return "settings:\(destination.rawValue)"
        case .runShortcut(let name): return "shortcut:\(name)"
        case .openFile(let path, let identifier, _): return "open-file:\(path):\(identifier ?? "default")"
        case .openProject(let path): return "open-project:\(path)"
        case .openTerminal(let directory): return "terminal:\(directory)"
        case .runRecipe(let identifier, _, _): return "recipe:\(identifier.uuidString)"
        case .wait(let seconds): return "wait:\(seconds)"
        }
    }

    var title: String {
        switch self {
        case .openApplication(_, let name): return "Open \(name)"
        case .revealApplication(_, let name): return "Show \(name) in Finder"
        case .openURL(let url): return "Open \(url.host ?? url.absoluteString)"
        case .openSystemSettings(let destination): return "Open \(destination.title)"
        case .runShortcut(let name): return "Run “\(name)”"
        case .openFile(let path, _, let app): return "Open \(URL(fileURLWithPath: path).lastPathComponent)\(app.map { " with \($0)" } ?? "")"
        case .openProject(let path): return "Open \(URL(fileURLWithPath: path).lastPathComponent)"
        case .openTerminal: return "Open Terminal Here"
        case .runRecipe(_, let name, _): return "Run “\(name)”"
        case .wait(let seconds): return "Wait \(seconds.formatted()) seconds"
        }
    }

    var preview: String {
        switch self {
        case .openApplication: return "Launches the selected installed application."
        case .revealApplication: return "Reveals the application bundle without changing it."
        case .openURL(let url): return url.absoluteString
        case .openSystemSettings(let destination): return "Opens \(destination.title) in System Settings."
        case .runShortcut: return "Runs a shortcut you explicitly selected. The shortcut may change files or other data."
        case .openFile(let path, _, _): return path
        case .openProject(let path): return path
        case .openTerminal(let directory): return directory
        case .runRecipe(_, _, let steps): return "Runs \(steps.count) deterministic local step\(steps.count == 1 ? "" : "s")."
        case .wait: return "Pauses before continuing the recipe."
        }
    }

    var historyTitle: String {
        switch self {
        case .runShortcut: return "Run approved Shortcut"
        case .openURL(let url): return "Open web link on \(url.host ?? "unknown host")"
        case .runRecipe: return "Run approved recipe"
        case .wait: return "Wait"
        default: return title
        }
    }

    var historyID: String {
        switch self {
        case .runShortcut: return "shortcut"
        case .openURL(let url): return "open-url:\(url.host ?? "unknown")"
        case .runRecipe: return "recipe"
        case .wait: return "clock"
        default: return id
        }
    }

    var requiresConfirmation: Bool {
        switch self {
        case .openApplication, .revealApplication, .openSystemSettings, .openFile, .openProject: return false
        case .openURL, .runShortcut, .openTerminal, .runRecipe: return true
        case .wait: return false
        }
    }
}

enum ActionRisk: String, Hashable, Sendable { case low, elevated }

struct ActionPreviewStep: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String

    init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
    }
}

struct ActionPreview: Identifiable, Hashable, Sendable {
    let action: LaunchDeckAction
    let title: String
    let summary: String
    let target: String
    let steps: [ActionPreviewStep]
    let permissions: [String]
    let risk: ActionRisk
    var id: String { action.id }

    init(action: LaunchDeckAction) {
        self.action = action
        title = action.title
        summary = action.preview
        switch action {
        case .openApplication(let id, _), .revealApplication(let id, _): target = id
        case .openURL(let url): target = url.absoluteString
        case .openSystemSettings(let destination): target = destination.title
        case .runShortcut(let name): target = name
        case .openFile(let path, _, _), .openProject(let path), .openTerminal(let path): target = path
        case .runRecipe(_, let name, _): target = name
        case .wait(let seconds): target = seconds.formatted()
        }
        switch action {
        case .runRecipe(_, _, let recipeSteps): steps = recipeSteps.map { ActionPreviewStep(id: $0.id, title: $0.summary) }
        case .wait: steps = [ActionPreviewStep(title: action.title)]
        default: steps = [ActionPreviewStep(title: action.title)]
        }
        switch action {
        case .runShortcut: permissions = ["Shortcuts may access data granted to that shortcut"]
        case .openTerminal: permissions = ["Opens Terminal at the selected directory"]
        case .runRecipe(_, _, let recipeSteps):
            var values = ["Runs every listed step in order"]
            if recipeSteps.contains(where: { if case .runShortcut = $0.operation { return true }; return false }) {
                values.append("Shortcuts may access data granted to those shortcuts")
            }
            if recipeSteps.contains(where: { if case .openTerminal = $0.operation { return true }; return false }) {
                values.append("Opens Terminal at the listed directories")
            }
            permissions = values
        default: permissions = []
        }
        risk = action.requiresConfirmation ? .elevated : .low
    }
}

enum SystemSettingsDestination: String, CaseIterable, Identifiable, Sendable {
    case appleIntelligence = "com.apple.preference.siri"
    case privacy = "com.apple.settings.PrivacySecurity.extension"
    case keyboard = "com.apple.Keyboard-Settings.extension"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .appleIntelligence: return "Apple Intelligence & Siri"
        case .privacy: return "Privacy & Security"
        case .keyboard: return "Keyboard Settings"
        }
    }
    var url: URL { URL(string: "x-apple.systempreferences:\(rawValue)")! }
}

struct ActionHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let actionID: String
    let title: String
    let date: Date
    let succeeded: Bool
}

enum ActionPolicy {
    static func validate(_ action: LaunchDeckAction, approvedShortcuts: Set<String>) -> String? {
        switch action {
        case .runShortcut(let name):
            return approvedShortcuts.contains(name) ? nil : "This shortcut has not been approved in LaunchDeck Settings."
        case .openURL(let url):
            return ["https", "http"].contains(url.scheme?.lowercased() ?? "") ? nil : "Only HTTP and HTTPS links can be opened."
        case .runRecipe(_, _, let steps):
            if let error = RecipeValidation.error(for: Recipe(name: "Validated Recipe", steps: steps)) { return error }
            if steps.contains(where: {
                if case .runShortcut(let name) = $0.operation { return !approvedShortcuts.contains(name) }
                return false
            }) { return "Every Shortcut used by this recipe must be approved in LaunchDeck Settings." }
            return steps.compactMap {
                guard RecipeRunner.conditionMatches($0.condition) else { return nil }
                return validate($0.action, approvedShortcuts: approvedShortcuts)
            }.first
        case .openFile(let path, _, _):
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                return "The target file does not exist."
            }
            return nil
        case .openProject(let path):
            return FileManager.default.fileExists(atPath: path) ? nil : "The target project or folder does not exist."
        case .openTerminal(let path):
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
                ? nil : "The Terminal target must be an existing directory."
        case .openApplication, .revealApplication, .openSystemSettings, .wait:
            return nil
        }
    }
}
