import AppKit
import Foundation

enum FileOperationError: LocalizedError, Equatable {
    case missingSource(String)
    case invalidName
    case destinationExists(String)
    case commandFailed(String)
    case unsupportedLink(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedLink(let value): "Only existing files and HTTP or HTTPS links can be opened: \(value)"
        case .missingSource(let path): "The source no longer exists: \(path)"
        case .invalidName: "Enter a valid file name without path separators."
        case .destinationExists(let path): "An item already exists at \(path)."
        case .commandFailed(let message): message
        }
    }
}

nonisolated struct FileUndoRecord: Codable, Hashable, Sendable {
    /// `source` is where the item is after the operation; undo moves it back to `destination`.
    nonisolated struct Move: Codable, Hashable, Sendable { let source: URL; let destination: URL }
    let title: String
    let moves: [Move]
    let createdURLs: [URL]

    /// The paths the operation removed and added, used to update the local index in place.
    var change: LocalContentChange {
        LocalContentChange(removedPaths: moves.map(\.destination.path),
                           addedURLs: moves.map(\.source) + createdURLs)
    }

    var undoChange: LocalContentChange {
        LocalContentChange(removedPaths: moves.map(\.source.path) + createdURLs.map(\.path),
                           addedURLs: moves.map(\.destination))
    }
}

nonisolated struct LocalContentChange: Hashable, Sendable {
    var removedPaths: [String] = []
    var addedURLs: [URL] = []

    static let none = LocalContentChange()
}

struct FileOperationService {
    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let recentDestinationKey = "fileOperations.recentDestinations.v1"

    init(fileManager: FileManager = .default, defaults: UserDefaults = .standard) {
        self.fileManager = fileManager
        self.defaults = defaults
    }

    var recentDestinationPaths: [String] {
        defaults.stringArray(forKey: recentDestinationKey) ?? []
    }

    func rename(_ source: URL, to newName: String) throws -> URL {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else { throw FileOperationError.invalidName }
        try requireSource(source)
        let destination = source.deletingLastPathComponent().appendingPathComponent(name)
        try requireAbsent(destination)
        try fileManager.moveItem(at: source, to: destination)
        return destination
    }

    func move(_ sources: [URL], to directory: URL) throws -> [URL] {
        var results: [URL] = []
        do {
            for source in sources {
                try requireSource(source)
                let destination = directory.appendingPathComponent(source.lastPathComponent)
                try requireAbsent(destination)
                try fileManager.moveItem(at: source, to: destination)
                results.append(destination)
            }
        } catch {
            for (destination, original) in zip(results, sources).reversed() where fileManager.fileExists(atPath: destination.path) {
                try? fileManager.moveItem(at: destination, to: original)
            }
            throw error
        }
        rememberDestination(directory)
        return results
    }

    func moveWithUndo(_ sources: [URL], to directory: URL) throws -> FileUndoRecord {
        let destinations = try move(sources, to: directory)
        return FileUndoRecord(title: "Move \(sources.count) Item\(sources.count == 1 ? "" : "s")",
                              moves: zip(destinations, sources).map { .init(source: $0.0, destination: $0.1) },
                              createdURLs: [])
    }

    func duplicate(_ source: URL) throws -> URL {
        try requireSource(source)
        let extensionName = source.pathExtension
        let base = source.deletingPathExtension().lastPathComponent
        let parent = source.deletingLastPathComponent()
        var counter = 1
        while true {
            let suffix = counter == 1 ? " copy" : " copy \(counter)"
            let filename = extensionName.isEmpty ? base + suffix : base + suffix + "." + extensionName
            let destination = parent.appendingPathComponent(filename)
            if !fileManager.fileExists(atPath: destination.path) {
                try fileManager.copyItem(at: source, to: destination)
                return destination
            }
            counter += 1
        }
    }

    func duplicateWithUndo(_ sources: [URL]) throws -> FileUndoRecord {
        var created: [URL] = []
        do { for source in sources { created.append(try duplicate(source)) } }
        catch {
            created.reversed().forEach { try? fileManager.removeItem(at: $0) }
            throw error
        }
        return FileUndoRecord(title: "Duplicate \(sources.count) Item\(sources.count == 1 ? "" : "s")",
                              moves: [], createdURLs: created)
    }

    func compress(_ source: URL) async throws -> URL {
        try requireSource(source)
        let destination = archiveDestination(for: source)
        let result: ProcessRunner.Result
        do {
            result = try await ProcessRunner.run(executable: "/usr/bin/ditto", arguments: [
                "-c", "-k", "--sequesterRsrc", "--keepParent", source.path, destination.path
            ])
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
        guard result.succeeded else {
            try? fileManager.removeItem(at: destination)
            throw FileOperationError.commandFailed(result.standardError)
        }
        return destination
    }

    /// Finder-style archive names: "a.pdf" → "a.pdf.zip", then "a.pdf 2.zip" if taken, so
    /// compressing "a.pdf" and "a.docx" together no longer collides on "a.zip".
    func archiveDestination(for source: URL) -> URL {
        let directory = source.deletingLastPathComponent()
        let name = source.lastPathComponent
        var candidate = directory.appendingPathComponent(name + ".zip")
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(name) \(counter).zip")
            counter += 1
        }
        return candidate
    }

    func compressWithUndo(_ sources: [URL]) async throws -> FileUndoRecord {
        var created: [URL] = []
        do { for source in sources { created.append(try await compress(source)) } }
        catch {
            created.reversed().forEach { try? fileManager.removeItem(at: $0) }
            throw error
        }
        return FileUndoRecord(title: "Compress \(sources.count) Item\(sources.count == 1 ? "" : "s")",
                              moves: [], createdURLs: created)
    }

    func setTags(_ tags: [String], on sources: [URL]) throws {
        let normalized = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        for source in sources {
            try requireSource(source)
            try (source as NSURL).setResourceValue(normalized, forKey: .tagNamesKey)
        }
    }

    @discardableResult
    func moveToTrash(_ sources: [URL]) throws -> FileUndoRecord {
        var moves: [FileUndoRecord.Move] = []
        do {
            for source in sources {
                try requireSource(source)
                var resultingURL: NSURL?
                try fileManager.trashItem(at: source, resultingItemURL: &resultingURL)
                if let resultingURL { moves.append(.init(source: resultingURL as URL, destination: source)) }
            }
        } catch {
            for move in moves.reversed() where fileManager.fileExists(atPath: move.source.path) {
                try? fileManager.moveItem(at: move.source, to: move.destination)
            }
            throw error
        }
        return FileUndoRecord(title: "Trash \(sources.count) Item\(sources.count == 1 ? "" : "s")",
                              moves: moves, createdURLs: [])
    }

    func undo(_ record: FileUndoRecord) throws {
        for url in record.createdURLs.reversed() where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        for move in record.moves.reversed() {
            try requireSource(move.source)
            try requireAbsent(move.destination)
            try fileManager.moveItem(at: move.source, to: move.destination)
        }
    }

    func clearRecentDestinations() {
        defaults.removeObject(forKey: recentDestinationKey)
    }

    private func rememberDestination(_ directory: URL) {
        let paths = [directory.path] + recentDestinationPaths.filter { $0 != directory.path }
        defaults.set(Array(paths.prefix(8)), forKey: recentDestinationKey)
    }

    private func requireSource(_ source: URL) throws {
        guard fileManager.fileExists(atPath: source.path) else { throw FileOperationError.missingSource(source.path) }
    }

    private func requireAbsent(_ destination: URL) throws {
        guard !fileManager.fileExists(atPath: destination.path) else { throw FileOperationError.destinationExists(destination.path) }
    }
}
