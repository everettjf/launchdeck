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
    case calculation, quicklink, emoji, clipboard, snippet, windowAction, extensionCommand
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
    case copyText(String)
    case url(URL)
    case systemCommand(String)
    case clipboardEntry(identifier: UUID)
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
        let query = FuzzyQuery(query)
        guard !query.isEmpty else { return [] }

        let recentPositions = Dictionary(recents.enumerated().map { ($0.element.identifier, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let layoutPositions = Dictionary(layout.enumerated().flatMap { index, item in
            item.containedAppIdentifiers.map { ($0, index) }
        }, uniquingKeysWith: { first, _ in first })

        let scored = entries.indices.compactMap { index -> (index: Int, score: Double)? in
            let entry = entries[index]
            guard let textScore = entry.field.score(query) else { return nil }
            var score = textScore
            if favorites.contains(entry.app.identifier) { score += 0.20 }
            if let position = recentPositions[entry.app.identifier] {
                score += max(0, 0.12 - Double(position) * 0.01)
            }
            if let position = layoutPositions[entry.app.identifier] {
                score += max(0, 0.08 - Double(position) * 0.003)
            }
            if !entry.app.isSystemApp { score += 0.01 }
            return (index, score)
        }
        return TopRanking.best(scored, limit: limit) { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return TopRanking.titleOrder(entries[lhs.index].field.title, entries[rhs.index].field.title)
                ?? (lhs.index < rhs.index)
        }
        .map { (entries[$0.index].app, $0.score) }
    }

    private struct Entry: Sendable {
        let app: DiscoveredApp
        let field: FuzzyField

        init(_ app: DiscoveredApp) {
            self.app = app
            field = FuzzyField(title: app.name,
                               metadata: [app.bundleIdentifier, app.developer, app.category].compactMap { $0 } + app.keywords)
        }
    }
}
