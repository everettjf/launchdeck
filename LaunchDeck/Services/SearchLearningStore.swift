import Foundation

struct SearchLearningSnapshot: Codable, Equatable {
    var selections: [String: [String: Int]] = [:]
    var recentQueries: [String] = []
    /// Queries with selections, most recently used first; bounds `selections`.
    var selectionOrder: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selections = try container.decodeIfPresent([String: [String: Int]].self, forKey: .selections) ?? [:]
        recentQueries = try container.decodeIfPresent([String].self, forKey: .recentQueries) ?? []
        selectionOrder = try container.decodeIfPresent([String].self, forKey: .selectionOrder)
            ?? Array(selections.keys.sorted())
    }
}

@MainActor
final class SearchLearningStore {
    private let defaults: UserDefaults
    private let key = "search.learning.v1"
    private(set) var snapshot: SearchLearningSnapshot
    private let maximumQueries: Int
    private let maximumItemsPerQuery: Int

    init(defaults: UserDefaults = .standard, maximumQueries: Int = 200, maximumItemsPerQuery: Int = 10) {
        self.defaults = defaults
        self.maximumQueries = maximumQueries
        self.maximumItemsPerQuery = maximumItemsPerQuery
        snapshot = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(SearchLearningSnapshot.self, from: $0) } ?? .init()
    }

    func boosts(for query: String) -> [String: Double] {
        snapshot.selections[normalize(query), default: [:]]
            .mapValues { min(0.30, log2(Double($0) + 1) * 0.08) }
    }

    func record(query: String, itemID: String) {
        let query = normalize(query)
        guard !query.isEmpty else { return }
        var counts = snapshot.selections[query, default: [:]]
        counts[itemID, default: 0] += 1
        if counts.count > maximumItemsPerQuery {
            // Keep the item just chosen plus the most-chosen others.
            let others = counts.filter { $0.key != itemID }
                .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                .prefix(maximumItemsPerQuery - 1)
            counts = Dictionary(uniqueKeysWithValues: others.map { ($0.key, $0.value) })
            counts[itemID] = 1
        }
        snapshot.selections[query] = counts
        snapshot.selectionOrder.removeAll { $0 == query }
        snapshot.selectionOrder.insert(query, at: 0)
        for evicted in snapshot.selectionOrder.dropFirst(maximumQueries) {
            snapshot.selections[evicted] = nil
        }
        snapshot.selectionOrder = Array(snapshot.selectionOrder.prefix(maximumQueries))
        snapshot.recentQueries.removeAll { $0 == query }
        snapshot.recentQueries.insert(query, at: 0)
        snapshot.recentQueries = Array(snapshot.recentQueries.prefix(30))
        defaults.set(try? JSONEncoder().encode(snapshot), forKey: key)
    }

    func clear() {
        snapshot = .init()
        defaults.removeObject(forKey: key)
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
