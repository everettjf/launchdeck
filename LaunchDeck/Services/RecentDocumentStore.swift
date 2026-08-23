import Foundation

nonisolated struct RecentDocumentEntry: Codable, Equatable, Identifiable, Sendable {
    let path: String
    let openedAt: Date
    var id: String { path }
}

nonisolated struct RecentDocumentStore: Sendable {
    let maximumCount: Int
    private let fileURL: URL

    init(maximumCount: Int = 30, fileURL: URL? = nil) {
        self.maximumCount = max(1, maximumCount)
        self.fileURL = fileURL ?? Self.defaultFileURL
    }

    func load(existingOnly: Bool = true) -> [RecentDocumentEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([RecentDocumentEntry].self, from: data) else { return [] }
        let filtered = existingOnly ? decoded.filter { FileManager.default.fileExists(atPath: $0.path) } : decoded
        return Array(filtered.sorted { $0.openedAt > $1.openedAt }.prefix(maximumCount))
    }

    @discardableResult
    func record(path: String, openedAt: Date = Date()) throws -> [RecentDocumentEntry] {
        let canonicalPath = URL(fileURLWithPath: path).standardizedFileURL.path
        var entries = load(existingOnly: false).filter { $0.path != canonicalPath }
        entries.insert(RecentDocumentEntry(path: canonicalPath, openedAt: openedAt), at: 0)
        entries = Array(entries.sorted { $0.openedAt > $1.openedAt }.prefix(maximumCount))
        try save(entries)
        return entries
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func save(_ entries: [RecentDocumentEntry]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
    }

    private static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("LaunchDeck", isDirectory: true)
            .appendingPathComponent("recent-documents-v1.json")
    }
}
