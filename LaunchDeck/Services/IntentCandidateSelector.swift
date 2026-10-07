import LaunchDeckCore

nonisolated enum IntentCandidateSelector {
    static func select(query: String,
                       index: UnifiedSearchIndex,
                       catalog: [String: SearchItem],
                       preferredFallbackIdentifiers: [String],
                       limit: Int = defaultLimit) -> [SearchItemCandidate] {
        guard limit > 0 else { return [] }
        let ranked = index.search(query, limit: limit)
        var candidates = ranked.map { SearchItemCandidate(item: $0.item, localScore: $0.score) }
        var seen = Set(candidates.map(\.id))
        func appendFallback(_ identifiers: some Sequence<String>) {
            for identifier in identifiers where candidates.count < limit {
                guard seen.insert(identifier).inserted, let item = catalog[identifier] else { continue }
                candidates.append(SearchItemCandidate(item: item, localScore: 0))
            }
        }
        appendFallback(preferredFallbackIdentifiers)
        // Sorting the whole catalog is only needed when preferred items cannot fill the list.
        if candidates.count < limit { appendFallback(catalog.keys.sorted()) }
        return candidates
    }

    /// Kept small so candidates, the action registry, instructions and up to eight structured
    /// matches fit in the on-device model's 4,096-token context window.
    static let defaultLimit = 20
}
