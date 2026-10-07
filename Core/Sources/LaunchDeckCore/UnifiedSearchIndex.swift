import Foundation

public struct UnifiedSearchIndex: Sendable {
    private let entries: [Entry]
    private let tokenPostings: [String: [Int]]

    public init(items: [SearchItem]) {
        let entries = items.map(Entry.init)
        self.entries = entries
        var postings: [String: [Int]] = [:]
        for (index, entry) in entries.enumerated() {
            for word in Set(entry.field.words) {
                postings[word, default: []].append(index)
            }
        }
        tokenPostings = postings
    }

    public func search(_ query: String, kindBoosts: [SearchItemKind: Double] = [:],
                       itemBoosts: [String: Double] = [:],
                       limit: Int? = nil) -> [(item: SearchItem, score: Double)] {
        let query = FuzzyQuery(query)
        guard !query.isEmpty else { return [] }
        let scored = candidateIndices(for: query.text).compactMap { index -> Scored? in
            let entry = entries[index]
            guard let score = entry.field.score(query) else { return nil }
            return Scored(index: index, score: score + (kindBoosts[entry.item.kind] ?? 0) + (itemBoosts[entry.item.id] ?? 0))
        }
        return rank(scored, limit: limit)
    }

    public func search(_ query: SearchQuery, kindBoosts: [SearchItemKind: Double] = [:],
                       itemBoosts: [String: Double] = [:], limit: Int? = nil) -> [(item: SearchItem, score: Double)] {
        let normalized = FuzzyQuery(query.text)
        let candidates = normalized.isEmpty ? Array(entries.indices) : candidateIndices(for: normalized.text)
        let matching = candidates.lazy.filter { query.matches(self.entries[$0].item) }
        let scored: [Scored]
        if normalized.isEmpty {
            scored = matching.map { Scored(index: $0, score: kindBoosts[entries[$0].item.kind] ?? 0) }
        } else {
            scored = matching.compactMap { index -> Scored? in
                let entry = entries[index]
                guard let score = entry.field.score(normalized) else { return nil }
                return Scored(index: index, score: score + (kindBoosts[entry.item.kind] ?? 0) + (itemBoosts[entry.item.id] ?? 0))
            }
        }
        return rank(scored, limit: limit)
    }

    private struct Scored {
        let index: Int
        let score: Double
    }

    /// Multi-token queries first use their complete words to avoid rescoring
    /// unrelated kinds. If any token is unknown we fall back to the complete
    /// index so typo-heavy queries retain the fuzzy matcher.
    private func candidateIndices(for query: String) -> [Int] {
        let tokens = FuzzyText.words(in: query)
        guard tokens.count > 1, let first = tokens.first, var indices = tokenPostings[first] else {
            return Array(entries.indices)
        }
        for token in tokens.dropFirst() {
            guard let posting = tokenPostings[token] else { return Array(entries.indices) }
            let allowed = Set(posting)
            indices.removeAll { !allowed.contains($0) }
            if indices.isEmpty { return Array(entries.indices) }
        }
        return indices
    }

    private func rank(_ values: [Scored], limit: Int?) -> [(item: SearchItem, score: Double)] {
        TopRanking.best(values, limit: limit) { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return TopRanking.titleOrder(entries[lhs.index].field.title, entries[rhs.index].field.title)
                ?? (lhs.index < rhs.index)
        }
        .map { (entries[$0.index].item, $0.score) }
    }

    private struct Entry: Sendable {
        let item: SearchItem
        let field: FuzzyField

        init(_ item: SearchItem) {
            self.item = item
            field = FuzzyField(title: item.title, metadata: [item.subtitle].compactMap { $0 } + item.keywords)
        }
    }
}
