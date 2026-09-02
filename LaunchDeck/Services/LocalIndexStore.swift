import Foundation
import LaunchDeckCore
import OSLog

private nonisolated let localIndexStoreLogger = Logger(subsystem: "com.everettjf.launchdeck", category: "LocalIndexStore")

nonisolated struct LocalIndexSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let rootPaths: [String]
    let indexedAt: Date
    let items: [SearchItem]

    init(rootPaths: [String], indexedAt: Date = Date(), items: [SearchItem]) {
        schemaVersion = Self.currentSchemaVersion
        self.rootPaths = Self.canonicalRootPaths(rootPaths)
        self.indexedAt = indexedAt
        self.items = items
    }

    static func canonicalRootPaths(_ paths: [String]) -> [String] {
        Array(Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })).sorted()
    }
}

nonisolated struct LocalIndexStore: Sendable {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
    }

    func load(expectedRootPaths: [String]) -> LocalIndexSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try JSONDecoder().decode(LocalIndexSnapshot.self, from: data)
            guard snapshot.schemaVersion == LocalIndexSnapshot.currentSchemaVersion,
                  snapshot.rootPaths == LocalIndexSnapshot.canonicalRootPaths(expectedRootPaths) else {
                localIndexStoreLogger.notice("Ignoring incompatible local index cache")
                return nil
            }
            return snapshot
        } catch {
            localIndexStoreLogger.error("Local index cache load failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func save(_ snapshot: LocalIndexSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("com.everettjf.launchdeck", isDirectory: true)
            .appendingPathComponent("local-index-v1.json")
    }
}
