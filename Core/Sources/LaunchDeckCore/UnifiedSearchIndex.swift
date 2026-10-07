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
        let query = Query(Self.normalize(query))
        guard !query.text.isEmpty else { return [] }
        let candidates = candidateIndices(for: query.text)
        let scored = candidates.compactMap { index -> Scored? in
            let entry = entries[index]
            guard let score = entry.score(query) else { return nil }
            return Scored(index: index, score: score + (kindBoosts[entry.item.kind] ?? 0) + (itemBoosts[entry.item.id] ?? 0))
        }
        return rank(scored, limit: limit)
    }

    public func search(_ query: SearchQuery, kindBoosts: [SearchItemKind: Double] = [:],
                       itemBoosts: [String: Double] = [:], limit: Int? = nil) -> [(item: SearchItem, score: Double)] {
        let normalized = Query(Self.normalize(query.text))
        let candidates = normalized.text.isEmpty ? Array(entries.indices) : candidateIndices(for: normalized.text)
        let matching = candidates.lazy.filter { query.matches(self.entries[$0].item) }
        let scored: [Scored]
        if normalized.text.isEmpty {
            scored = matching.map { Scored(index: $0, score: kindBoosts[entries[$0].item.kind] ?? 0) }
        } else {
            scored = matching.compactMap { index -> Scored? in
                let entry = entries[index]
                guard let score = entry.score(normalized) else { return nil }
                return Scored(index: index, score: score + (kindBoosts[entry.item.kind] ?? 0) + (itemBoosts[entry.item.id] ?? 0))
            }
        }
        return rank(scored, limit: limit)
    }

    /// A query normalized once per search rather than once per scored entry.
    private struct Query {
        let text: String
        let compact: String
        let count: Int

        init(_ text: String) {
            self.text = text
            compact = text.replacingOccurrences(of: " ", with: "")
            count = text.count
        }
    }

    private struct Scored {
        let index: Int
        let score: Double
    }

    /// Multi-token queries first use their complete words to avoid rescoring
    /// unrelated kinds. If any token is unknown we fall back to the complete
    /// index so typo-heavy queries retain the fuzzy matcher.
    private func candidateIndices(for query: String) -> [Int] {
        let tokens = Self.words(query)
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

    /// Keeps only the best requested results in a small worst-first heap. The
    /// launcher asks for at most 80 rows, so this avoids sorting every match in
    /// broad one-character searches while preserving the exact final ordering.
    private func rank(_ values: [Scored], limit: Int?) -> [(item: SearchItem, score: Double)] {
        let result: [Scored]
        if let limit {
            guard limit > 0 else { return [] }
            var heap: [Scored] = []
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
            result = heap.sorted(by: isBetter)
        } else {
            result = values.sorted(by: isBetter)
        }
        return result.map { (entries[$0.index].item, $0.score) }
    }

    /// Ties are broken by the normalized title's bytes, which avoids a
    /// locale-aware comparison for every heap operation.
    private func isBetter(_ lhs: Scored, _ rhs: Scored) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        let left = entries[lhs.index], right = entries[rhs.index]
        // Titles are already case, width and diacritic folded, so byte order is a stable key.
        if left.title != right.title { return left.title.utf8.lexicographicallyPrecedes(right.title.utf8) }
        return lhs.index < rhs.index
    }

    private func siftWorstUp(_ heap: inout [Scored], from start: Int) {
        var child = start
        while child > 0 {
            let parent = (child - 1) / 2
            guard isBetter(heap[parent], heap[child]) else { return }
            heap.swapAt(child, parent)
            child = parent
        }
    }

    private func siftWorstDown(_ heap: inout [Scored], from start: Int) {
        var parent = start
        while true {
            let left = parent * 2 + 1
            guard left < heap.count else { return }
            let right = left + 1
            let worstChild = right < heap.count && isBetter(heap[left], heap[right]) ? right : left
            guard isBetter(heap[parent], heap[worstChild]) else { return }
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
        let titleCount: Int

        init(_ item: SearchItem) {
            self.item = item
            title = UnifiedSearchIndex.normalize(item.title)
            titleCount = title.count
            let all = ([item.title, item.subtitle].compactMap { $0 } + item.keywords)
                .joined(separator: " ")
            words = UnifiedSearchIndex.words(all)
            secondary = UnifiedSearchIndex.normalize(all)
            initials = words.compactMap(\.first).map(String.init).joined()
        }

        func score(_ normalized: Query) -> Double? {
            let query = normalized.text
            if title == query { return 1 }
            if title.hasPrefix(query) { return 0.92 - min(Double(max(0, titleCount - normalized.count)) * 0.002, 0.08) }
            if words.contains(query) { return 0.88 }
            if words.contains(where: { $0.hasPrefix(query) }) { return 0.82 }
            if initials.hasPrefix(normalized.compact) { return 0.79 }
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
