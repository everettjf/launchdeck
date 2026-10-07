import Combine
import Foundation
import LaunchDeckCore
import OSLog

private nonisolated let localContentLogger = Logger(subsystem: "com.everettjf.launchdeck", category: "LocalContent")

/// Owns the local file index: the cached snapshot, background rescans, recently opened
/// documents and in-place updates after file operations.
@MainActor
final class LocalContentCoordinator: ObservableObject {
    @Published private(set) var items: [SearchItem] = []
    /// Called whenever `items` changes so the unified index can be rebuilt.
    var itemsChanged: () -> Void = {}

    private let store: LocalIndexStore
    private let recentDocumentStore: RecentDocumentStore
    private let rootPaths: () -> [String]
    private var generation = 0
    private var task: Task<Void, Never>?

    init(store: LocalIndexStore, recentDocumentStore: RecentDocumentStore, rootPaths: @escaping () -> [String]) {
        self.store = store
        self.recentDocumentStore = recentDocumentStore
        self.rootPaths = rootPaths
    }

    /// Shows the cached snapshot first, then rescans every root in the background.
    func refresh(rootPaths requestedRootPaths: [String]? = nil) {
        generation += 1
        let requestGeneration = generation
        task?.cancel()
        let rootPaths = requestedRootPaths ?? self.rootPaths()
        let roots = rootPaths.map(URL.init(fileURLWithPath:))
        let store = store
        let recentDocumentStore = recentDocumentStore
        task = Task.detached(priority: .utility) { [weak self] in
            if let cached = store.load(expectedRootPaths: rootPaths) {
                guard !Task.isCancelled else { return }
                await self?.apply(cached.items, generation: requestGeneration, source: "cache")
            }

            let startedAt = ContinuousClock.now
            let storedRecentURLs = recentDocumentStore.load().map { URL(fileURLWithPath: $0.path) }
            let items = LocalContentIndexer().index(configuration: .init(roots: roots),
                                                    recentURLs: storedRecentURLs,
                                                    isCancelled: { Task.isCancelled })
            guard !Task.isCancelled else { return }
            do {
                try store.save(LocalIndexSnapshot(rootPaths: rootPaths, items: items))
            } catch {
                localContentLogger.error("Local index cache save failed: \(error.localizedDescription, privacy: .public)")
            }
            guard !Task.isCancelled else { return }
            await self?.apply(items, generation: requestGeneration, source: "scan", elapsed: startedAt.duration(to: .now))
        }
    }

    /// Updates the index in place after a file operation. Only a new or moved directory, whose
    /// contents a single-path update cannot cover, falls back to a full rescan.
    func apply(_ change: LocalContentChange) {
        guard change != .none else { return }
        let roots = rootPaths().map(URL.init(fileURLWithPath:))
        let addsDirectory = change.addedURLs.contains { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
                && !["xcodeproj", "xcworkspace", "playground"].contains(url.pathExtension.lowercased())
                && roots.contains { url.path.hasPrefix($0.path + "/") }
        }
        if addsDirectory {
            refresh()
            return
        }
        let removed = Set(change.removedPaths + change.addedURLs.map(\.path))
        items.removeAll { item in
            guard let path = item.fileSystemPath else { return false }
            return removed.contains(path) || removed.contains { path.hasPrefix($0 + "/") }
        }
        let indexer = LocalContentIndexer()
        items += change.addedURLs.compactMap { indexer.item(for: $0, roots: roots) }
        itemsChanged()
        persist()
    }

    /// Opening a document only needs that one item in the index, not a rescan of every root.
    func recordRecentDocument(_ path: String) {
        _ = try? recentDocumentStore.record(path: path)
        guard !items.contains(where: { $0.fileSystemPath == path }),
              let item = LocalContentIndexer().recentItem(for: URL(fileURLWithPath: path)) else { return }
        items.append(item)
        itemsChanged()
        persist()
    }

    /// Part of the privacy reset: forgets recent documents and the cached index, then rescans.
    func clearHistory() {
        try? recentDocumentStore.clear()
        try? store.clear()
        items = []
        itemsChanged()
        refresh()
    }

    private func persist() {
        let snapshot = LocalIndexSnapshot(rootPaths: rootPaths(), items: items)
        let store = store
        Task.detached(priority: .utility) {
            do { try store.save(snapshot) }
            catch { localContentLogger.error("Local index cache save failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    private func apply(_ items: [SearchItem], generation: Int, source: String, elapsed: Duration? = nil) {
        guard generation == self.generation else { return }
        self.items = items
        itemsChanged()
        if let elapsed {
            localContentLogger.info("Local index \(source, privacy: .public) completed count=\(items.count) duration=\(elapsed.milliseconds, format: .fixed(precision: 1))ms")
        } else {
            localContentLogger.info("Local index cache restored count=\(items.count)")
        }
    }
}

extension Duration {
    nonisolated var milliseconds: Double {
        let components = components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
