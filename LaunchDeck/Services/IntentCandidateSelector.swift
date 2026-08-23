import LaunchDeckCore

nonisolated enum IntentCandidateSelector {
    static func select(query: String,
                       index: UnifiedSearchIndex,
                       catalog: [String: SearchItem],
                       preferredFallbackIdentifiers: [String],
                       limit: Int = 40) -> [SearchItemCandidate] {
        guard limit > 0 else { return [] }
        let ranked = index.search(query, limit: limit)
        let rankedIDs = Set(ranked.map(\.item.id))
        var seen = Set<String>()
        let fallback = (preferredFallbackIdentifiers + catalog.keys.sorted()).compactMap { identifier -> SearchItem? in
            guard !rankedIDs.contains(identifier), seen.insert(identifier).inserted else { return nil }
            return catalog[identifier]
        }
        return Array((ranked.map { SearchItemCandidate(item: $0.item, localScore: $0.score) }
                      + fallback.map { SearchItemCandidate(item: $0, localScore: 0) })
            .prefix(limit))
    }
}
