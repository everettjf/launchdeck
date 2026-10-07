import AppKit
import Foundation

@MainActor
struct ObjectActionPerformer {
    private let files: FileOperationService

    init(files: FileOperationService = FileOperationService()) { self.files = files }

    func execute(kind: RecipeStep.ObjectActionKind, sources: [String], target: String?) async throws -> FileUndoRecord? {
        let fileURLs = sources.filter { FileManager.default.fileExists(atPath: $0) }.map(URL.init(fileURLWithPath:))
        // File actions must not report success after quietly dropping a source that vanished.
        if [.reveal, .openWith, .move, .duplicate, .compress, .trash].contains(kind),
           let missing = sources.first(where: { !FileManager.default.fileExists(atPath: $0) }) {
            throw FileOperationError.missingSource(missing)
        }
        switch kind {
        case .open:
            let targets = try sources.map(Self.openTarget)
            targets.forEach { NSWorkspace.shared.open($0) }
        case .reveal:
            guard !fileURLs.isEmpty else { throw FileOperationError.commandFailed("Reveal requires a file or folder.") }
            NSWorkspace.shared.activateFileViewerSelecting(fileURLs)
        case .copy:
            writePasteboard(sources: sources)
        case .paste:
            writePasteboard(sources: sources)
            paste(into: target)
        case .openWith:
            guard let target else { throw FileOperationError.commandFailed("Choose an application target.") }
            let applicationURL = URL(fileURLWithPath: target)
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(fileURLs, withApplicationAt: applicationURL, configuration: configuration, completionHandler: nil)
        case .move:
            guard let target else { throw FileOperationError.commandFailed("Choose a destination folder.") }
            return try files.moveWithUndo(fileURLs, to: URL(fileURLWithPath: target))
        case .duplicate: return try files.duplicateWithUndo(fileURLs)
        case .compress: return try await files.compressWithUndo(fileURLs)
        case .trash: return try files.moveToTrash(fileURLs)
        }
        return nil
    }

    /// Resolves an Open source to an existing file or a web link. Other schemes (`file:` URLs to
    /// scripts, custom app schemes) could run code, so they are refused.
    static func openTarget(_ value: String) throws -> URL {
        if FileManager.default.fileExists(atPath: value) { return URL(fileURLWithPath: value) }
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw FileOperationError.unsupportedLink(String(value.prefix(120)))
        }
        return url
    }

    private func writePasteboard(sources: [String]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let URLs = sources.filter { FileManager.default.fileExists(atPath: $0) }.map { NSURL(fileURLWithPath: $0) }
        if URLs.count == sources.count, !URLs.isEmpty { pasteboard.writeObjects(URLs) }
        else { pasteboard.setString(sources.joined(separator: "\n"), forType: .string) }
    }

    private func paste(into bundleIdentifier: String?) {
        if let bundleIdentifier,
           let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            application.activate(options: [.activateAllWindows])
        } else {
            NSApp.hide(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
            let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            down?.flags = .maskCommand; up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        }
    }
}
