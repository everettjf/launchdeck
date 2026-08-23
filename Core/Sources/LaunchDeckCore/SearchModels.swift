import Foundation

public struct AppCandidate: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let category: String?
    public let developer: String?
    public let keywords: [String]
    public let localScore: Double

    public init(app: DiscoveredApp, localScore: Double) {
        id = app.identifier
        name = app.name
        category = app.category
        developer = app.developer
        keywords = app.keywords
        self.localScore = localScore
    }
}

public enum SearchItemKind: String, CaseIterable, Codable, Hashable, Sendable {
    case application, file, folder, project, action, setting, shortcut, recipe
}

public enum SearchItemTarget: Codable, Hashable, Sendable {
    case application(identifier: String, path: String)
    case file(path: String)
    case folder(path: String)
    case project(path: String)
    case registeredAction(identifier: String)
    case systemSetting(identifier: String)
    case shortcut(name: String)
    case recipe(identifier: UUID)
}

public struct SearchItem: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let kind: SearchItemKind
    public let title: String
    public let subtitle: String?
    public let keywords: [String]
    public let target: SearchItemTarget

    public init(id: String, kind: SearchItemKind, title: String, subtitle: String? = nil,
                keywords: [String] = [], target: SearchItemTarget) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.target = target
    }
}

public struct SearchItemCandidate: Identifiable, Hashable, Sendable {
    public let item: SearchItem
    public let localScore: Double
    public var id: String { item.id }

    public init(item: SearchItem, localScore: Double) {
        self.item = item
        self.localScore = localScore
    }
}

public struct IntentRecommendation: Identifiable, Hashable, Sendable {
    public let targetIdentifier: String
    public let actionIdentifier: String
    public let parameters: [String: String]
    public let missingParameters: [String]
    public let confidence: Double
    public let reason: String
    public let requiresConfirmation: Bool

    public var id: String { "\(targetIdentifier):\(actionIdentifier)" }

    public init(targetIdentifier: String, actionIdentifier: String,
                parameters: [String: String] = [:], missingParameters: [String] = [],
                confidence: Double, reason: String, requiresConfirmation: Bool) {
        self.targetIdentifier = targetIdentifier
        self.actionIdentifier = actionIdentifier
        self.parameters = parameters
        self.missingParameters = Array(missingParameters.prefix(8))
        self.confidence = min(max(confidence, 0), 1)
        self.reason = String(reason.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180))
        self.requiresConfirmation = requiresConfirmation
    }
}

public enum IntentRecommendationValidator {
    public static func validate(_ results: [IntentRecommendation], allowedTargets: Set<String>,
                                allowedActions: Set<String>, limit: Int = 8) -> [IntentRecommendation] {
        var seen = Set<String>()
        return results
            .filter { allowedTargets.contains($0.targetIdentifier)
                && allowedActions.contains($0.actionIdentifier)
                && seen.insert($0.id).inserted }
            .sorted { $0.confidence > $1.confidence }
            .prefix(limit)
            .map { $0 }
    }
}

public struct IntentResult: Identifiable, Hashable, Sendable {
    public let appIdentifier: String
    public let confidence: Double
    public let reason: String
    public let matchedCapabilities: [String]

    public var id: String { appIdentifier }

    public init(appIdentifier: String,
                confidence: Double,
                reason: String,
                matchedCapabilities: [String] = []) {
        self.appIdentifier = appIdentifier
        self.confidence = min(max(confidence, 0), 1)
        self.reason = String(reason.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180))
        self.matchedCapabilities = matchedCapabilities
    }
}

public enum IntentResultValidator {
    public static func validate(_ results: [IntentResult],
                                allowedIdentifiers: Set<String>,
                                limit: Int = 8) -> [IntentResult] {
        var seen = Set<String>()
        return results
            .filter { allowedIdentifiers.contains($0.appIdentifier) && seen.insert($0.appIdentifier).inserted }
            .sorted { $0.confidence > $1.confidence }
            .prefix(limit)
            .map { $0 }
    }
}

public enum IntentUnavailableReason: String, Hashable, Sendable {
    case requiresMacOS26
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unknown
}

public enum IntentSearchAvailability: Hashable, Sendable {
    case checking
    case available
    case unavailable(IntentUnavailableReason)
}

public enum IntentSearchPhase: Hashable, Sendable {
    case idle
    case waiting
    case searching
    case completed
    case failed(String)
}

public struct SearchIndex: Sendable {
    private let entries: [Entry]

    public init(apps: [DiscoveredApp]) {
        entries = apps.map(Entry.init)
    }

    public func search(_ query: String,
                       favorites: Set<String> = [],
                       recents: [RecentLaunch] = [],
                       layout: [AppCollectionItem] = [],
                       limit: Int? = nil) -> [(app: DiscoveredApp, score: Double)] {
        let normalizedQuery = Self.normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let recentPositions = Dictionary(uniqueKeysWithValues: recents.enumerated().map { ($0.element.identifier, $0.offset) })
        let layoutPositions = Dictionary(uniqueKeysWithValues: layout.enumerated().flatMap { index, item in
            item.containedAppIdentifiers.map { ($0, index) }
        })

        let ranked = entries.compactMap { entry -> (DiscoveredApp, Double)? in
            guard let textScore = entry.matchScore(for: normalizedQuery) else { return nil }
            var score = textScore
            if favorites.contains(entry.app.identifier) { score += 0.20 }
            if let position = recentPositions[entry.app.identifier] {
                score += max(0, 0.12 - Double(position) * 0.01)
            }
            if let position = layoutPositions[entry.app.identifier] {
                score += max(0, 0.08 - Double(position) * 0.003)
            }
            if !entry.app.isSystemApp { score += 0.01 }
            return (entry.app, score)
        }
        .sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
        }

        if let limit { return Array(ranked.prefix(limit)) }
        return ranked
    }

    private struct Entry: Sendable {
        let app: DiscoveredApp
        let name: String
        let words: [String]
        let secondary: String
        let initials: String

        init(_ app: DiscoveredApp) {
            self.app = app
            name = SearchIndex.normalize(app.name)
            let all = ([app.name, app.bundleIdentifier, app.developer, app.category]
                .compactMap { $0 } + app.keywords).joined(separator: " ")
            words = SearchIndex.words(in: all)
            secondary = SearchIndex.normalize(all)
            initials = words.compactMap(\.first).map(String.init).joined()
        }

        func matchScore(for query: String) -> Double? {
            if name == query { return 1.00 }
            if name.hasPrefix(query) { return 0.92 - lengthPenalty(query, in: name) }
            if words.contains(query) { return 0.88 }
            if words.contains(where: { $0.hasPrefix(query) }) { return 0.82 }
            if initials.hasPrefix(query.replacingOccurrences(of: " ", with: "")) { return 0.79 }
            if let range = name.range(of: query) {
                return 0.72 - Double(name.distance(from: name.startIndex, to: range.lowerBound)) * 0.003
            }
            if let subsequence = subsequenceScore(query, in: name) { return 0.58 + subsequence * 0.12 }
            if isLikelyTypo(query, of: name) { return 0.54 }
            if secondary.contains(query) { return 0.45 }
            if let word = words.first(where: { isLikelyTypo(query, of: $0) }) {
                return 0.43 - lengthPenalty(query, in: word)
            }
            return nil
        }

        private func lengthPenalty(_ query: String, in value: String) -> Double {
            min(Double(max(0, value.count - query.count)) * 0.002, 0.08)
        }

        private func subsequenceScore(_ query: String, in value: String) -> Double? {
            var queryIndex = query.startIndex
            var matchedIndices: [String.Index] = []
            for index in value.indices where queryIndex < query.endIndex {
                if value[index] == query[queryIndex] {
                    matchedIndices.append(index)
                    query.formIndex(after: &queryIndex)
                }
            }
            guard queryIndex == query.endIndex, let first = matchedIndices.first, let last = matchedIndices.last else { return nil }
            let span = value.distance(from: first, to: last) + 1
            return Double(query.count) / Double(max(span, query.count))
        }

        private func editDistance(_ lhs: String, _ rhs: String) -> Int {
            var left = Array(lhs)
            var right = Array(rhs)
            while !left.isEmpty, !right.isEmpty, left.first == right.first {
                left.removeFirst()
                right.removeFirst()
            }
            while !left.isEmpty, !right.isEmpty, left.last == right.last {
                left.removeLast()
                right.removeLast()
            }
            if left.isEmpty { return right.count }
            if right.isEmpty { return left.count }
            var previousPrevious: [Int]?
            var previous = Array(0...right.count)
            for (leftIndex, leftCharacter) in left.enumerated() {
                var current = [leftIndex + 1]
                for (rightIndex, rightCharacter) in right.enumerated() {
                    var distance = min(
                        current[rightIndex] + 1,
                        previous[rightIndex + 1] + 1,
                        previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                    )
                    if leftIndex > 0,
                       rightIndex > 0,
                       leftCharacter == right[rightIndex - 1],
                       left[leftIndex - 1] == rightCharacter,
                       let previousPrevious {
                        distance = min(distance, previousPrevious[rightIndex - 1] + 1)
                    }
                    current.append(distance)
                }
                previousPrevious = previous
                previous = current
            }
            return previous[right.count]
        }

        private func typoTolerance(_ length: Int) -> Int { length >= 8 ? 2 : 1 }

        private func isLikelyTypo(_ query: String, of value: String) -> Bool {
            guard query.count >= 4 else { return false }
            let tolerance = typoTolerance(query.count)
            guard abs(query.count - value.count) <= tolerance,
                  query.first == value.first else { return false }
            return editDistance(query, value) <= tolerance
        }
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func words(in value: String) -> [String] {
        normalize(value).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
