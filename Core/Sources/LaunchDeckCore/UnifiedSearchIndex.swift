import Foundation

public struct UnifiedSearchIndex: Sendable {
    private let entries: [Entry]
    private let tokenPostings: [String: [Int]]

    public init(items: [SearchItem]) {
        let entries = items.map(Entry.init)
        self.entries = entries
        var postings: [String: [Int]] = [:]
        for (index, entry) in entries.enumerated() {
            for word in Set(entry.words) {
                postings[word, default: []].append(index)
            }
        }
        tokenPostings = postings
    }

    public func search(_ query: String, kindBoosts: [SearchItemKind: Double] = [:],
                       itemBoosts: [String: Double] = [:],
                       limit: Int? = nil) -> [(item: SearchItem, score: Double)] {
        let query = Self.normalize(query)
        guard !query.isEmpty else { return [] }
        let candidates = candidateEntries(for: query)
        let scored = candidates.compactMap { entry -> (SearchItem, Double)? in
            guard let score = entry.score(query) else { return nil }
            return (entry.item, score + (kindBoosts[entry.item.kind] ?? 0) + (itemBoosts[entry.item.id] ?? 0))
        }
        return Self.rank(scored, limit: limit)
    }

    public func search(_ query: SearchQuery, kindBoosts: [SearchItemKind: Double] = [:],
                       itemBoosts: [String: Double] = [:], limit: Int? = nil) -> [(item: SearchItem, score: Double)] {
        let normalized = Self.normalize(query.text)
        let candidates = normalized.isEmpty ? entries : candidateEntries(for: normalized)
        let matching = candidates.lazy.filter { query.matches($0.item) }
        let ranked: [(SearchItem, Double)]
        if normalized.isEmpty {
            let scored: [(SearchItem, Double)] = matching.map { ($0.item, kindBoosts[$0.item.kind] ?? 0) }
            ranked = Self.rank(scored, limit: limit)
        } else {
            let scored: [(SearchItem, Double)] = matching.compactMap { entry -> (SearchItem, Double)? in
                guard let score = entry.score(normalized) else { return nil }
                return (entry.item, score + (kindBoosts[entry.item.kind] ?? 0) + (itemBoosts[entry.item.id] ?? 0))
            }
            ranked = Self.rank(scored, limit: limit)
        }
        return ranked
    }

    /// Multi-token queries first use their complete words to avoid rescoring
    /// unrelated kinds. If any token is unknown we fall back to the complete
    /// index so typo-heavy queries retain the fuzzy matcher.
    private func candidateEntries(for query: String) -> [Entry] {
        let tokens = Self.words(query)
        guard tokens.count > 1, let first = tokens.first, var indices = tokenPostings[first] else {
            return entries
        }
        for token in tokens.dropFirst() {
            guard let posting = tokenPostings[token] else { return entries }
            let allowed = Set(posting)
            indices.removeAll { !allowed.contains($0) }
            if indices.isEmpty { return entries }
        }
        return indices.map { entries[$0] }
    }

    /// Keeps only the best requested results in a small worst-first heap. The
    /// launcher asks for at most 80 rows, so this avoids sorting every match in
    /// broad one-character searches while preserving the exact final ordering.
    private static func rank(_ values: [(SearchItem, Double)], limit: Int?) -> [(item: SearchItem, score: Double)] {
        guard let limit else { return values.sorted(by: isBetter) }
        guard limit > 0 else { return [] }
        var heap: [(SearchItem, Double)] = []
        heap.reserveCapacity(min(limit, values.count))

        for value in values {
            if heap.count < limit {
                heap.append(value)
                siftWorstUp(&heap, from: heap.count - 1)
            } else if let worst = heap.first, isBetter(value, worst) {
                heap[0] = value
                siftWorstDown(&heap, from: 0)
            }
        }
        return heap.sorted(by: isBetter)
    }

    private static func isBetter(_ lhs: (SearchItem, Double), _ rhs: (SearchItem, Double)) -> Bool {
        if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
        return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
    }

    private static func isWorse(_ lhs: (SearchItem, Double), _ rhs: (SearchItem, Double)) -> Bool {
        isBetter(rhs, lhs)
    }

    private static func siftWorstUp(_ heap: inout [(SearchItem, Double)], from start: Int) {
        var child = start
        while child > 0 {
            let parent = (child - 1) / 2
            guard isWorse(heap[child], heap[parent]) else { return }
            heap.swapAt(child, parent)
            child = parent
        }
    }

    private static func siftWorstDown(_ heap: inout [(SearchItem, Double)], from start: Int) {
        var parent = start
        while true {
            let left = parent * 2 + 1
            guard left < heap.count else { return }
            let right = left + 1
            let worstChild = right < heap.count && isWorse(heap[right], heap[left]) ? right : left
            guard isWorse(heap[worstChild], heap[parent]) else { return }
            heap.swapAt(parent, worstChild)
            parent = worstChild
        }
    }

    private struct Entry: Sendable {
        let item: SearchItem
        let title: String
        let words: [String]
        let secondary: String
        let initials: String

        init(_ item: SearchItem) {
            self.item = item
            title = UnifiedSearchIndex.normalize(item.title)
            let all = ([item.title, item.subtitle].compactMap { $0 } + item.keywords)
                .joined(separator: " ")
            words = UnifiedSearchIndex.words(all)
            secondary = UnifiedSearchIndex.normalize(all)
            initials = words.compactMap(\.first).map(String.init).joined()
        }

        func score(_ query: String) -> Double? {
            if title == query { return 1 }
            if title.hasPrefix(query) { return 0.92 - penalty(query, title) }
            if words.contains(query) { return 0.88 }
            if words.contains(where: { $0.hasPrefix(query) }) { return 0.82 }
            let compact = query.replacingOccurrences(of: " ", with: "")
            if initials.hasPrefix(compact) { return 0.79 }
            if let range = title.range(of: query) {
                return 0.72 - Double(title.distance(from: title.startIndex, to: range.lowerBound)) * 0.003
            }
            if let quality = subsequence(query, title) { return 0.58 + quality * 0.12 }
            if typo(query, title) { return 0.54 }
            if secondary.contains(query) { return 0.45 }
            if let word = words.first(where: { typo(query, $0) }) { return 0.43 - penalty(query, word) }
            return nil
        }

        private func penalty(_ query: String, _ value: String) -> Double {
            min(Double(max(0, value.count - query.count)) * 0.002, 0.08)
        }

        private func subsequence(_ query: String, _ value: String) -> Double? {
            var queryIndex = query.startIndex
            var first: String.Index?
            var last: String.Index?
            for index in value.indices where queryIndex < query.endIndex {
                if value[index] == query[queryIndex] {
                    first = first ?? index
                    last = index
                    query.formIndex(after: &queryIndex)
                }
            }
            guard queryIndex == query.endIndex, let first, let last else { return nil }
            return Double(query.count) / Double(max(value.distance(from: first, to: last) + 1, query.count))
        }

        private func typo(_ query: String, _ value: String) -> Bool {
            guard query.count >= 4 else { return false }
            let tolerance = query.count >= 8 ? 2 : 1
            guard abs(query.count - value.count) <= tolerance, query.first == value.first else { return false }
            return editDistance(query, value) <= tolerance
        }

        private func editDistance(_ lhs: String, _ rhs: String) -> Int {
            let left = Array(lhs), right = Array(rhs)
            var previous = Array(0...right.count)
            for (leftIndex, leftCharacter) in left.enumerated() {
                var current = [leftIndex + 1]
                for (rightIndex, rightCharacter) in right.enumerated() {
                    current.append(min(current[rightIndex] + 1,
                                       previous[rightIndex + 1] + 1,
                                       previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)))
                }
                previous = current
            }
            return previous[right.count]
        }
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func words(_ value: String) -> [String] {
        normalize(value).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
