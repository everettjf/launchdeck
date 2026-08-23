import AppKit
import Foundation

enum FileOperationError: LocalizedError, Equatable {
    case missingSource(String)
    case invalidName
    case destinationExists(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingSource(let path): "The source no longer exists: \(path)"
        case .invalidName: "Enter a valid file name without path separators."
        case .destinationExists(let path): "An item already exists at \(path)."
        case .commandFailed(let message): message
        }
    }
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
        for source in sources {
            try requireSource(source)
            let destination = directory.appendingPathComponent(source.lastPathComponent)
            try requireAbsent(destination)
            try fileManager.moveItem(at: source, to: destination)
            results.append(destination)
        }
        rememberDestination(directory)
        return results
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

    func compress(_ source: URL) throws -> URL {
        try requireSource(source)
        let destination = source.deletingPathExtension().appendingPathExtension("zip")
        try requireAbsent(destination)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, destination.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            throw FileOperationError.commandFailed(String(decoding: data, as: UTF8.self))
        }
        return destination
    }

    func setTags(_ tags: [String], on sources: [URL]) throws {
        let normalized = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        for source in sources {
            try requireSource(source)
            try (source as NSURL).setResourceValue(normalized, forKey: .tagNamesKey)
        }
    }

    func moveToTrash(_ sources: [URL]) throws {
        for source in sources {
            try requireSource(source)
            _ = try fileManager.trashItem(at: source, resultingItemURL: nil)
        }
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
