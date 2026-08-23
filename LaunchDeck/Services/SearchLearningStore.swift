import Foundation

struct SearchLearningSnapshot: Codable, Equatable {
    var selections: [String: [String: Int]] = [:]
    var recentQueries: [String] = []
}

@MainActor
final class SearchLearningStore {
    private let defaults: UserDefaults
    private let key = "search.learning.v1"
    private(set) var snapshot: SearchLearningSnapshot

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        snapshot.selections[query, default: [:]][itemID, default: 0] += 1
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
