import Combine
import Foundation
import LaunchDeckCore
import OSLog

private nonisolated let unifiedIndexLogger = Logger(subsystem: "com.everettjf.launchdeck", category: "UnifiedIndex")

private nonisolated struct UnifiedIndexSnapshot: Sendable {
    let catalog: [String: SearchItem]
    let index: UnifiedSearchIndex

    init(items: [SearchItem]) {
        catalog = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        index = UnifiedSearchIndex(items: items)
    }
}

/// Builds the unified search catalog (apps, local files, shortcuts, recipes) off the main actor
/// and publishes a new revision whenever a newer build lands.
@MainActor
final class UnifiedIndexCoordinator: ObservableObject {
    @Published private(set) var revision = 0
    private(set) var index = UnifiedSearchIndex(items: [])
    private(set) var catalog: [String: SearchItem] = [:]
    private var generation = 0
    private var task: Task<Void, Never>?

    func rebuild(apps: [DiscoveredApp], indexedItems: [SearchItem], approvedShortcuts: [String], recipes: [Recipe]) {
        generation += 1
        let requestGeneration = generation
        task?.cancel()
        let startedAt = ContinuousClock.now
        task = Task.detached(priority: .userInitiated) { [weak self] in
            let items = SearchCatalogBuilder.build(apps: apps, indexedItems: indexedItems,
                                                   approvedShortcuts: approvedShortcuts, recipes: recipes)
            let snapshot = UnifiedIndexSnapshot(items: items)
            guard !Task.isCancelled else { return }
            await self?.apply(snapshot, generation: requestGeneration, elapsed: startedAt.duration(to: .now))
        }
    }

    func item(identifier: String) -> SearchItem? { catalog[identifier] }

    private func apply(_ snapshot: UnifiedIndexSnapshot, generation: Int, elapsed: Duration) {
        guard generation == self.generation else { return }
        catalog = snapshot.catalog
        index = snapshot.index
        revision &+= 1
        unifiedIndexLogger.debug("Unified index built count=\(snapshot.catalog.count) duration=\(elapsed.milliseconds, format: .fixed(precision: 1))ms")
    }
}
