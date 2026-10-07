import AppKit
import Combine
import Foundation
import LaunchDeckCore
import SwiftUI

/// Object → Action → Target chains, search-result context actions and file operations.
extension AppState {
    func receiveInstantSend(_ objects: [LaunchObject]) {
        instantSendObjects = objects
    }

    func clearInstantSend() { instantSendObjects = [] }

    func objectTargets(for action: ObjectAction) -> [LaunchObject] {
        switch action {
        case .move:
            let recent = fileOperationService.recentDestinationPaths.map {
                LaunchObject(kind: .folder, title: URL(fileURLWithPath: $0).lastPathComponent, value: $0)
            }
            let indexed = indexedItems.compactMap(LaunchObject.init(searchItem:)).filter { $0.kind == .folder }
            var seen = Set<String>()
            return (recent + indexed).filter { seen.insert($0.value).inserted }
        case .openWith:
            return allApps().map {
                LaunchObject(kind: .application, title: $0.name, value: $0.path, applicationIdentifier: $0.identifier)
            }
        default: return []
        }
    }

    func perform(_ action: ObjectAction, sources: [LaunchObject], target: LaunchObject?) {
        guard !sources.isEmpty else { return }
        if action == .saveAsRecipe {
            saveObjectChainAsRecipe(sources: sources, target: target)
            return
        }
        guard let kind = recipeKind(for: action) else { return }
        let clipboardEntries = sources.compactMap { source -> ClipboardEntry? in
            guard source.kind == .clipboard, let id = UUID(uuidString: source.value) else { return nil }
            return clipboardStore.entries.first { $0.id == id }
        }
        if clipboardEntries.count == sources.count, let first = clipboardEntries.first, [.copy, .paste].contains(action) {
            if action == .paste { clipboardStore.paste(first) } else { clipboardStore.writeToPasteboard(first) }
            return
        }
        let targetValue: String?
        if action == .paste { targetValue = sources.first?.applicationIdentifier }
        else { targetValue = target?.value }
        Task { [weak self, objectActionPerformer] in
            do {
                let undo = try await objectActionPerformer.execute(kind: kind, sources: sources.map(\.value), target: targetValue)
                guard let self else { return }
                if let undo {
                    self.objectUndoManager.registerUndo(withTarget: self) { state in state.undoObjectAction(undo) }
                    self.objectUndoManager.setActionName(undo.title)
                }
                self.applyLocalContentChange(undo?.change ?? .none)
            } catch { self?.actionController.presentError(error.localizedDescription) }
        }
    }

    func undoLastObjectAction() {
        guard objectUndoManager.canUndo else { return }
        objectUndoManager.undo()
    }

    private func undoObjectAction(_ record: FileUndoRecord) {
        do { try fileOperationService.undo(record); applyLocalContentChange(record.undoChange) }
        catch { actionController.presentError("Undo failed: \(error.localizedDescription)") }
    }

    private func saveObjectChainAsRecipe(sources: [LaunchObject], target: LaunchObject?) {
        guard let name = UserPrompt.text(title: "Save Action Chain", message: "Recipe name:", value: "Object Workflow") else { return }
        // The saved default is an open chain; the navigator replaces this with its selected action when supplied.
        let recipe = Recipe(name: name, steps: [.objectAction(.open, sources: sources.map(\.value), target: target?.value)])
        do { try recipeStore.save(recipe) }
        catch { actionController.presentError(error.localizedDescription) }
    }

    func saveObjectChainAsRecipe(action: ObjectAction, sources: [LaunchObject], target: LaunchObject?) {
        guard let kind = recipeKind(for: action),
              let name = UserPrompt.text(title: "Save Action Chain", message: "Recipe name:", value: "\(action.title) Workflow") else { return }
        let savedTarget = action == .paste ? (target?.value ?? sources.first?.applicationIdentifier) : target?.value
        let recipe = Recipe(name: name, steps: [.objectAction(kind, sources: sources.map(\.value), target: savedTarget)])
        do { try recipeStore.save(recipe) }
        catch { actionController.presentError(error.localizedDescription) }
    }

    private func recipeKind(for action: ObjectAction) -> RecipeStep.ObjectActionKind? {
        switch action {
        case .open: .open
        case .reveal: .reveal
        case .copy: .copy
        case .paste: .paste
        case .openWith: .openWith
        case .move: .move
        case .duplicate: .duplicate
        case .compress: .compress
        case .trash: .trash
        case .saveAsRecipe: nil
        }
    }

    // Called when search query changes - handles semantic search state

    func contextualActions(for item: SearchItem) -> [SearchContextAction] {
        SearchContextActionCatalog.actions(for: item)
    }

    func perform(_ contextAction: SearchContextAction, on item: SearchItem) {
        switch contextAction {
        case .open:
            perform(item)
        case .reveal:
            reveal(item)
        case .quickLook:
            guard let path = item.fileSystemPath else { return }
            QuickLookCoordinator.shared.preview(path: path)
        case .copyPath:
            guard let path = item.fileSystemPath else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        case .openTerminal:
            guard let path = item.fileSystemPath else { return }
            var isDirectory: ObjCBool = false
            let directory = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
                ? path : URL(fileURLWithPath: path).deletingLastPathComponent().path
            requestAction(.openTerminal(directory: directory))
        case .rename:
            guard let url = item.fileSystemURL,
                  let name = UserPrompt.text(title: "Rename \(url.lastPathComponent)", message: "Enter a new name:", value: url.lastPathComponent) else { return }
            runFileOperation { [fileOperationService] in
                let renamed = try fileOperationService.rename(url, to: name)
                return LocalContentChange(removedPaths: [url.path], addedURLs: [renamed])
            }
        case .move:
            guard let url = item.fileSystemURL else { return }
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Move Here"
            if let recent = fileOperationService.recentDestinationPaths.first {
                panel.directoryURL = URL(fileURLWithPath: recent)
            }
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            runFileOperation { [fileOperationService] in try fileOperationService.moveWithUndo([url], to: destination).change }
        case .duplicate:
            guard let url = item.fileSystemURL else { return }
            runFileOperation { [fileOperationService] in LocalContentChange(addedURLs: [try fileOperationService.duplicate(url)]) }
        case .compress:
            guard let url = item.fileSystemURL else { return }
            runFileOperation { [fileOperationService] in LocalContentChange(addedURLs: [try await fileOperationService.compress(url)]) }
        case .tag:
            guard let url = item.fileSystemURL,
                  let value = UserPrompt.text(title: "Set Finder Tags", message: "Enter comma-separated tags:", value: "") else { return }
            runFileOperation { [fileOperationService] in
                try fileOperationService.setTags(value.split(separator: ",").map(String.init), on: [url])
                return .none
            }
        case .trash:
            guard let url = item.fileSystemURL else { return }
            let alert = NSAlert()
            alert.messageText = "Move “\(url.lastPathComponent)” to Trash?"
            alert.informativeText = "The item can be recovered from the Trash."
            alert.addButton(withTitle: "Move to Trash")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            runFileOperation { [fileOperationService] in try fileOperationService.moveToTrash([url]).change }
        case .paste:
            guard case .clipboardEntry(let identifier) = item.target,
                  let entry = clipboardStore.entries.first(where: { $0.id == identifier }) else { return }
            clipboardStore.paste(entry)
        }
    }

    private func runFileOperation(_ operation: @escaping () async throws -> LocalContentChange) {
        Task { [weak self] in
            do {
                let change = try await operation()
                self?.applyLocalContentChange(change)
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }

    private func reveal(_ item: SearchItem) {
        switch item.target {
        case .application(let identifier, _):
            guard let app = appsByIdentifier[identifier] else { return }
            requestAction(.revealApplication(identifier: identifier, name: app.name))
        default:
            guard let path = item.fileSystemPath else { return }
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    }

    func perform(_ item: SearchItem) {
        let learningQuery = searchQuery.hasPrefix("/") ? String(searchQuery.dropFirst()) : searchQuery
        searchLearningStore.record(query: learningQuery, itemID: item.id)
        recentSearchQueries = searchLearningStore.snapshot.recentQueries
        if let recommendation = intentResults.first(where: { $0.targetIdentifier == item.id }) {
            let appName: String?
            if case .application(let identifier, _) = item.target { appName = appsByIdentifier[identifier]?.name }
            else { appName = nil }
            switch IntentActionResolver.resolve(recommendation, target: item, applicationName: appName,
                                                installedApplications: appsByIdentifier.mapValues { $0.name },
                                                recipes: recipeStore.recipes) {
            case .action(let action):
                requestAction(action)
                return
            case .missingParameters(let missing):
                actionController.presentError("This action needs: \(missing.joined(separator: ", ")). Refine the intent or choose a concrete target.")
                return
            case .unresolved:
                actionController.presentError("The suggested action could not be resolved safely.")
                return
            }
        }
        let action: LaunchDeckAction?
        switch item.target {
        case .application(let identifier, _):
            action = appsByIdentifier[identifier].map { .openApplication(identifier: identifier, name: $0.name) }
        case .file(let path): action = .openFile(path: path, applicationIdentifier: nil, applicationName: nil)
        case .folder(let path), .project(let path): action = .openProject(path: path)
        case .registeredAction(let identifier):
            if identifier == "open.terminal" {
                action = .openTerminal(directory: FileManager.default.homeDirectoryForCurrentUser.path)
            } else {
                action = nil
                actionController.presentError("“\(identifier)” needs a concrete target. Use intent search or select a file, project, app, or recipe.")
            }
        case .systemSetting(let identifier):
            action = SystemSettingsDestination(rawValue: identifier).map { .openSystemSettings(destination: $0) }
        case .shortcut(let name): action = .runShortcut(name: name)
        case .recipe(let identifier):
            if let recipe = recipeStore.recipes.first(where: { $0.id == identifier }) { runRecipe(recipe) }
            action = nil
        case .copyText(let value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            action = nil
        case .url(let url): action = .openURL(url)
        case .systemCommand(let identifier):
            if let command = DesktopWindowCommand(rawValue: identifier),
               let error = DesktopWindowController.perform(command) { actionController.presentError(error) }
            action = nil
        case .clipboardEntry(let identifier):
            if let entry = clipboardStore.entries.first(where: { $0.id == identifier }) { clipboardStore.writeToPasteboard(entry) }
            action = nil
        }
        if let action { requestAction(action) }
    }
}

private extension SearchItem {
    var fileSystemURL: URL? { fileSystemPath.map { URL(fileURLWithPath: $0) } }
}
