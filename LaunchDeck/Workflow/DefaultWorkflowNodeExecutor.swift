import AppKit
import Foundation

@MainActor
final class DefaultWorkflowNodeExecutor: WorkflowNodeExecuting {
    enum ExecutionError: LocalizedError {
        case unsupported(String)
        case missingInput(String)
        case permissionDenied(String)
        var errorDescription: String? {
            switch self {
            case .unsupported(let value): "Unsupported workflow block: \(value)"
            case .missingInput(let value): "Missing workflow input: \(value)"
            case .permissionDenied(let value): "Workflow permission denied: \(value)"
            }
        }
    }

    private let performer: ObjectActionPerformer
    private let AI: WorkflowAIService
    var instantSendProvider: () -> [LaunchObject]
    var approvedShortcutsProvider: () -> Set<String>

    init(performer: ObjectActionPerformer = ObjectActionPerformer(), AI: WorkflowAIService,
         instantSendProvider: @escaping () -> [LaunchObject] = { [] },
         approvedShortcutsProvider: @escaping () -> Set<String> = { [] }) {
        self.performer = performer
        self.AI = AI
        self.instantSendProvider = instantSendProvider
        self.approvedShortcutsProvider = approvedShortcutsProvider
    }

    func execute(node: WorkflowNode, inputs: [String: WorkflowValue], workflow: WorkflowDefinition) async throws -> WorkflowNodeExecutionResult {
        switch node.kindIdentifier {
        case "input.instant-send":
            return deterministic(["objects": .collection(instantSendProvider().map(WorkflowValue.object)), "control": .none])
        case "input.files":
            return deterministic(["objects": inputs["objects"] ?? .collection([]), "control": .none])
        case "input.clipboard":
            return deterministic(["value": clipboardValue(), "control": .none])
        case "data.text": return deterministic(["value": inputs["value"] ?? inputs["prompt"] ?? .text(""), "control": .none])
        case "data.folder": return deterministic(["value": inputs["value"] ?? inputs["target"] ?? .folder(""), "control": .none])
        case "logic.delay":
            let seconds: Double = if case .number(let value) = inputs["seconds"] { value } else { 1.0 }
            try await Task.sleep(for: .seconds(max(0, seconds)))
            return deterministic(["control": .none])
        case "logic.approval":
            guard node.configuration["approved"] == .boolean(true) else {
                throw ExecutionError.missingInput("Approval")
            }
            return deterministic(["control": .none])
        case "output.copy":
            let value = inputs["value"] ?? .none
            let pasteboard = NSPasteboard.general; pasteboard.clearContents()
            pasteboard.setString(value.stringValue ?? "", forType: .string)
            return deterministic(["control": .none])
        case "action.open-application":
            guard let identifier = inputs["identifier"]?.stringValue,
                  let URL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
                throw ExecutionError.missingInput("Installed application")
            }
            let opened = await withCheckedContinuation { continuation in
                NSWorkspace.shared.openApplication(at: URL, configuration: .init()) { app, _ in
                    continuation.resume(returning: app != nil)
                }
            }
            guard opened else { throw ExecutionError.unsupported("Could not open application") }
            return deterministic(["control": .none])
        case "action.open-terminal":
            guard let directory = inputs["directory"]?.stringValue else { throw ExecutionError.missingInput("Directory") }
            let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            let configuration = NSWorkspace.OpenConfiguration(); configuration.arguments = [directory]
            let opened = await withCheckedContinuation { continuation in
                NSWorkspace.shared.openApplication(at: terminal, configuration: configuration) { app, _ in
                    continuation.resume(returning: app != nil)
                }
            }
            guard opened else { throw ExecutionError.unsupported("Could not open Terminal") }
            return deterministic(["control": .none])
        case "action.run-shortcut":
            guard let name = inputs["shortcut"]?.stringValue else { throw ExecutionError.missingInput("Shortcut") }
            guard approvedShortcutsProvider().contains(name) else { throw ExecutionError.permissionDenied("Shortcut “\(name)” is not approved") }
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts"); process.arguments = ["run", name]
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw ExecutionError.unsupported("Shortcut failed") }
            return deterministic(["control": .none])
        case let identifier where identifier.hasPrefix("ai."):
            let task = String(identifier.dropFirst(3))
            let input = inputs["input"] ?? inputs["objects"] ?? .none
            let instruction = inputs["prompt"]?.stringValue ?? node.configuration["prompt"]?.stringValue ?? node.title
            let policy = node.configuration["modelPolicy"]?.stringValue.flatMap(WorkflowModelPolicy.init(rawValue:)) ?? workflow.policy.modelPolicy
            let dataPolicy = node.configuration["dataPolicy"]?.stringValue.flatMap(WorkflowDataPolicy.init(rawValue:)) ?? workflow.policy.dataPolicy
            let approved = node.configuration["providerApproved"] == .boolean(true) || node.configuration["pccApproved"] == .boolean(true)
            let result = try await AI.execute(task: task, input: input, instruction: instruction,
                                              modelPolicy: policy, dataPolicy: dataPolicy,
                                              providerApproved: approved)
            return .init(outputs: ["result": result.value, "control": .none], route: result.route, undoOperation: nil)
        case let identifier where identifier.hasPrefix("action."):
            return try executeAction(identifier: identifier, inputs: inputs)
        default: throw ExecutionError.unsupported(node.kindIdentifier)
        }
    }

    private func executeAction(identifier: String, inputs: [String: WorkflowValue]) throws -> WorkflowNodeExecutionResult {
        let objects = objects(from: inputs["objects"] ?? .collection([]))
        let sources = objects.map(\.value)
        let target = inputs["target"]?.stringValue
        let kind: RecipeStep.ObjectActionKind
        switch identifier {
        case "action.open": kind = .open
        case "action.copy": kind = .copy
        case "action.move": kind = .move
        case "action.duplicate": kind = .duplicate
        case "action.compress": kind = .compress
        case "action.trash": kind = .trash
        case "action.reveal": kind = .reveal
        case "action.paste": kind = .paste
        case "action.openWith": kind = .openWith
        default: throw ExecutionError.unsupported(identifier)
        }
        if sources.isEmpty { throw ExecutionError.missingInput("Objects") }
        let undo = try performer.execute(kind: kind, sources: sources, target: target)
        return .init(outputs: ["objects": .collection(objects.map(WorkflowValue.object)), "control": .none],
                     route: .deterministic, undoOperation: undo.map(WorkflowUndoOperation.init))
    }

    private func deterministic(_ outputs: [String: WorkflowValue]) -> WorkflowNodeExecutionResult {
        .init(outputs: outputs, route: .deterministic, undoOperation: nil)
    }

    private func objects(from value: WorkflowValue) -> [LaunchObject] {
        switch value {
        case .object(let object): [object]
        case .file(let path): [LaunchObject(kind: .file, title: URL(fileURLWithPath: path).lastPathComponent, value: path)]
        case .folder(let path): [LaunchObject(kind: .folder, title: URL(fileURLWithPath: path).lastPathComponent, value: path)]
        case .url(let value): [LaunchObject(kind: .url, title: value, value: value)]
        case .text(let value): [LaunchObject(kind: .text, title: String(value.prefix(80)), value: value)]
        case .collection(let values): values.flatMap { objects(from: $0) }
        default: []
        }
    }

    private func clipboardValue() -> WorkflowValue {
        let pasteboard = NSPasteboard.general
        if let URLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !URLs.isEmpty {
            return .collection(URLs.map { .file($0.path) })
        }
        if let data = pasteboard.data(forType: .png) { return .image(data) }
        return .text(pasteboard.string(forType: .string) ?? "")
    }
}
