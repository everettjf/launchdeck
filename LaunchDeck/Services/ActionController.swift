import AppKit
import Combine
import Foundation

@MainActor
final class ActionController: ObservableObject {
    @Published private(set) var pendingPreview: ActionPreview?
    var pendingAction: LaunchDeckAction? { pendingPreview?.action }
    @Published private(set) var lastError: String?

    private let historyStore: ActionHistoryStore
    var appProvider: (String) -> URL?
    var applicationOpened: (String) -> Void = { _ in }
    var documentOpened: (String) -> Void = { _ in }

    init(historyStore: ActionHistoryStore = ActionHistoryStore(),
         appProvider: @escaping (String) -> URL? = { _ in nil }) {
        self.historyStore = historyStore
        self.appProvider = appProvider
    }

    func request(_ action: LaunchDeckAction, approvedShortcuts: Set<String> = []) {
        lastError = nil
        if let validationError = ActionPolicy.validate(action, approvedShortcuts: approvedShortcuts) {
            fail(action, message: validationError)
            return
        }
        if action.requiresConfirmation {
            pendingPreview = ActionPreview(action: action)
        } else {
            execute(action)
        }
    }

    func cancelPending() { pendingPreview = nil }
    func dismissError() { lastError = nil }
    func presentError(_ message: String) { lastError = message }

    func confirmPending() {
        guard let action = pendingPreview?.action else { return }
        pendingPreview = nil
        execute(action)
    }

    func clearHistory() { historyStore.clear() }

    private func execute(_ action: LaunchDeckAction) {
        switch action {
        case .openApplication(let identifier, _):
            guard let url = appProvider(identifier) else { fail(action, message: "The application is no longer installed."); return }
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { [weak self] running, error in
                Task { @MainActor in
                    if let error { self?.fail(action, message: error.localizedDescription) }
                    else {
                        let succeeded = running != nil
                        self?.historyStore.record(action: action, succeeded: succeeded)
                        if succeeded { self?.applicationOpened(identifier) }
                    }
                }
            }
        case .revealApplication(let identifier, _):
            guard let url = appProvider(identifier) else { fail(action, message: "The application is no longer installed."); return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
            historyStore.record(action: action, succeeded: true)
        case .openURL(let url):
            complete(action, succeeded: NSWorkspace.shared.open(url))
        case .openSystemSettings(let destination):
            complete(action, succeeded: NSWorkspace.shared.open(destination.url))
        case .runShortcut(let name):
            Task { [weak self] in
                let succeeded = await Self.runProcess(executable: "/usr/bin/shortcuts", arguments: ["run", name])
                self?.complete(action, succeeded: succeeded)
            }
        case .openFile(let path, let applicationIdentifier, _):
            let url = URL(fileURLWithPath: path)
            if let applicationIdentifier {
                guard let applicationURL = appProvider(applicationIdentifier) else {
                    fail(action, message: "The selected application is no longer installed.")
                    return
                }
                let configuration = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open([url], withApplicationAt: applicationURL, configuration: configuration) { [weak self] _, error in
                    Task { @MainActor in
                        if let error { self?.fail(action, message: error.localizedDescription) }
                        else {
                            self?.complete(action, succeeded: true)
                            self?.documentOpened(path)
                        }
                    }
                }
            } else {
                let succeeded = NSWorkspace.shared.open(url)
                complete(action, succeeded: succeeded)
                if succeeded { documentOpened(path) }
            }
        case .openProject(let path):
            let succeeded = NSWorkspace.shared.open(URL(fileURLWithPath: path))
            complete(action, succeeded: succeeded)
            if succeeded { documentOpened(path) }
        case .openTerminal(let directory):
            let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = [directory]
            NSWorkspace.shared.openApplication(at: terminal, configuration: configuration) { [weak self] _, error in
                Task { @MainActor in
                    if let error { self?.fail(action, message: error.localizedDescription) }
                    else { self?.complete(action, succeeded: true) }
                }
            }
        case .runRecipe(_, _, let steps):
            executeRecipe(steps, parent: action)
        }
    }

    private func executeRecipe(_ steps: [RecipeStep], parent: LaunchDeckAction) {
        Task { [weak self] in
            guard let self else { return }
            let succeeded = await RecipeRunner.run(steps) { [weak self] step in
                guard let self else { return false }
                return await self.executeRecipeStep(step.action)
            }
            self.complete(parent, succeeded: succeeded)
        }
    }

    private func executeRecipeStep(_ action: LaunchDeckAction) async -> Bool {
        switch action {
        case .openApplication(let identifier, _):
            guard let url = appProvider(identifier) else { return false }
            let succeeded = await withCheckedContinuation { continuation in
                NSWorkspace.shared.openApplication(at: url, configuration: .init()) { running, _ in
                    continuation.resume(returning: running != nil)
                }
            }
            if succeeded { applicationOpened(identifier) }
            return succeeded
        case .openProject(let path):
            let succeeded = NSWorkspace.shared.open(URL(fileURLWithPath: path))
            if succeeded { documentOpened(path) }
            return succeeded
        case .openTerminal(let path):
            let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            let configuration = NSWorkspace.OpenConfiguration(); configuration.arguments = [path]
            return await withCheckedContinuation { continuation in
                NSWorkspace.shared.openApplication(at: terminal, configuration: configuration) { running, _ in
                    continuation.resume(returning: running != nil)
                }
            }
        case .runShortcut(let name):
            return await Self.runProcess(executable: "/usr/bin/shortcuts", arguments: ["run", name])
        default: return false
        }
    }

    private nonisolated static func runProcess(executable: String, arguments: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.terminationHandler = { process in continuation.resume(returning: process.terminationStatus == 0) }
            do { try process.run() } catch { continuation.resume(returning: false) }
        }
    }

    private func complete(_ action: LaunchDeckAction, succeeded: Bool) {
        historyStore.record(action: action, succeeded: succeeded)
        if !succeeded { lastError = "The action could not be completed." }
    }

    private func fail(_ action: LaunchDeckAction, message: String) {
        lastError = message
        historyStore.record(action: action, succeeded: false)
    }
}
