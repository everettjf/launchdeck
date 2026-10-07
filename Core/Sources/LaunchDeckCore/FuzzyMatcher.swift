import Foundation

/// Text matching shared by `SearchIndex` (applications) and `UnifiedSearchIndex` (everything),
/// so both rank exact, prefix, word, initials, substring, subsequence and typo matches the same
/// way and changes to scoring land in one place.
enum FuzzyText {
    static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func words(in value: String) -> [String] {
        normalize(value).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

/// A query normalized once per search rather than once per scored entry.
struct FuzzyQuery: Sendable {
    let text: String
    let compact: String
    let count: Int

    init(_ raw: String) {
        text = FuzzyText.normalize(raw)
        compact = text.replacingOccurrences(of: " ", with: "")
        count = text.count
    }

    var isEmpty: Bool { text.isEmpty }
}

/// The searchable form of one item: its title plus every other searchable string.
struct FuzzyField: Sendable {
    let title: String
    let titleCount: Int
    let words: [String]
    let secondary: String
    let initials: String

    init(title: String, metadata: [String]) {
        self.title = FuzzyText.normalize(title)
        titleCount = self.title.count
        let all = ([title] + metadata).joined(separator: " ")
        words = FuzzyText.words(in: all)
        secondary = FuzzyText.normalize(all)
        initials = words.compactMap(\.first).map(String.init).joined()
    }

    func score(_ query: FuzzyQuery) -> Double? {
        let text = query.text
        if title == text { return 1.00 }
        if title.hasPrefix(text) { return 0.92 - Self.lengthPenalty(query.count, titleCount) }
        if words.contains(text) { return 0.88 }
        if words.contains(where: { $0.hasPrefix(text) }) { return 0.82 }
        if initials.hasPrefix(query.compact) { return 0.79 }
        if let range = title.range(of: text) {
            return 0.72 - Double(title.distance(from: title.startIndex, to: range.lowerBound)) * 0.003
        }
        if let subsequence = Self.subsequenceScore(text, in: title) { return 0.58 + subsequence * 0.12 }
        if Self.isLikelyTypo(text, queryCount: query.count, of: title) { return 0.54 }
        if secondary.contains(text) { return 0.45 }
        if let word = words.first(where: { Self.isLikelyTypo(text, queryCount: query.count, of: $0) }) {
            return 0.43 - Self.lengthPenalty(query.count, word.count)
        }
        return nil
    }

    private static func lengthPenalty(_ queryCount: Int, _ valueCount: Int) -> Double {
        min(Double(max(0, valueCount - queryCount)) * 0.002, 0.08)
    }

    private static func subsequenceScore(_ query: String, in value: String) -> Double? {
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

    private static func isLikelyTypo(_ query: String, queryCount: Int, of value: String) -> Bool {
        guard queryCount >= 4 else { return false }
        let tolerance = queryCount >= 8 ? 2 : 1
        guard abs(queryCount - value.count) <= tolerance, query.first == value.first else { return false }
        return editDistance(query, value) <= tolerance
    }

    /// Damerau–Levenshtein (optimal string alignment) distance, so a swapped pair of letters
    /// ("saafri" for "safari") counts as one edit. Shared prefixes and suffixes are trimmed first.
    static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        var left = Array(lhs)[...]
        var right = Array(rhs)[...]
        while let l = left.first, let r = right.first, l == r { left.removeFirst(); right.removeFirst() }
        while let l = left.last, let r = right.last, l == r { left.removeLast(); right.removeLast() }
        let a = Array(left), b = Array(right)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previousPrevious: [Int]?
        var previous = Array(0...b.count)
        for (i, leftCharacter) in a.enumerated() {
            var current = [i + 1]
            for (j, rightCharacter) in b.enumerated() {
                var distance = min(current[j] + 1, previous[j + 1] + 1,
                                   previous[j] + (leftCharacter == rightCharacter ? 0 : 1))
                if i > 0, j > 0, leftCharacter == b[j - 1], a[i - 1] == rightCharacter, let previousPrevious {
                    distance = min(distance, previousPrevious[j - 1] + 1)
                }
                current.append(distance)
            }
            previousPrevious = previous
            previous = current
        }
        return previous[b.count]
    }
}

/// Keeps only the best `limit` values in a small worst-first heap. Launcher searches ask for at
/// most 80 rows, so broad one-character queries avoid sorting every match while the final order
/// stays exact.
enum TopRanking {
    static func best<Value>(_ values: [Value], limit: Int?, isBetter: (Value, Value) -> Bool) -> [Value] {
        guard let limit else { return values.sorted(by: isBetter) }
        guard limit > 0 else { return [] }
        var heap: [Value] = []
        heap.reserveCapacity(min(limit, values.count))
        for value in values {
            if heap.count < limit {
                heap.append(value)
                var child = heap.count - 1
                while child > 0 {
                    let parent = (child - 1) / 2
                    guard isBetter(heap[parent], heap[child]) else { break }
                    heap.swapAt(child, parent)
                    child = parent
                }
            } else if let worst = heap.first, isBetter(value, worst) {
                heap[0] = value
                var parent = 0
                while true {
                    let left = parent * 2 + 1
                    guard left < heap.count else { break }
                    let right = left + 1
                    let worstChild = right < heap.count && isBetter(heap[left], heap[right]) ? right : left
                    guard isBetter(heap[parent], heap[worstChild]) else { break }
                    heap.swapAt(parent, worstChild)
                    parent = worstChild
                }
            }
        }
        return heap.sorted(by: isBetter)
    }

    /// Ties are broken by normalized title bytes, avoiding a locale-aware comparison per heap step.
    static func titleOrder(_ lhs: String, _ rhs: String) -> Bool? {
        lhs == rhs ? nil : lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }
}
