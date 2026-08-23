import Foundation
import FoundationModels
import LaunchDeckCore
import OSLog

private nonisolated let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LaunchDeck", category: "IntentSearch")

protocol IntentSearching: Sendable {
    func availability() async -> IntentSearchAvailability
    func search(query: String, candidates: [SearchItemCandidate]) async throws -> [IntentRecommendation]
}

enum IntentSearcherFactory {
    static func make() -> any IntentSearching {
        if #available(macOS 26.0, *) {
            return FoundationModelsIntentSearcher()
        }
        return UnavailableIntentSearcher(reason: .requiresMacOS26)
    }
}

actor UnavailableIntentSearcher: IntentSearching {
    let reason: IntentUnavailableReason
    init(reason: IntentUnavailableReason) { self.reason = reason }
    func availability() -> IntentSearchAvailability { .unavailable(reason) }
    func search(query: String, candidates: [SearchItemCandidate]) async throws -> [IntentRecommendation] { [] }
}

@available(macOS 26.0, *)
@Generable
private struct GeneratedParameter {
    var name: String
    var value: String
}

@available(macOS 26.0, *)
@Generable(description: "One installed application that can satisfy the user's intent")
private struct GeneratedIntentMatch {
    @Guide(description: "The exact candidate identifier")
    var targetIdentifier: String
    @Guide(description: "The exact registered action identifier")
    var actionIdentifier: String
    @Guide(description: "Action parameter names and values", .maximumCount(8))
    var parameters: [GeneratedParameter]
    @Guide(description: "Required parameters that cannot be inferred", .maximumCount(8))
    var missingParameters: [String]
    @Guide(description: "Relevance confidence from 0 through 100", .range(0...100))
    var confidence: Int
    @Guide(description: "A short reason, no more than one sentence")
    var reason: String
    @Guide(description: "Short capability labels that matched the intent", .maximumCount(4))
    var capabilities: [String]
    @Guide(description: "Whether the action must be confirmed")
    var requiresConfirmation: Bool
}

@available(macOS 26.0, *)
@Generable
private struct GeneratedIntentResponse {
    @Guide(description: "At most eight relevant installed applications", .maximumCount(8))
    var matches: [GeneratedIntentMatch]
}

@available(macOS 26.0, *)
actor FoundationModelsIntentSearcher: IntentSearching {
    private let model = SystemLanguageModel.default

    func availability() -> IntentSearchAvailability {
        switch model.availability {
        case .available: return .available
        case .unavailable(.deviceNotEligible): return .unavailable(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled): return .unavailable(.appleIntelligenceNotEnabled)
        case .unavailable(.modelNotReady): return .unavailable(.modelNotReady)
        case .unavailable: return .unavailable(.unknown)
        }
    }

    func search(query: String, candidates: [SearchItemCandidate]) async throws -> [IntentRecommendation] {
        guard case .available = availability(), !candidates.isEmpty else { return [] }
        let candidateText = candidates.map { candidate in
            let item = candidate.item
            return "ID: \(item.id) | Type: \(item.kind.rawValue) | Name: \(item.title) | Metadata: \(item.subtitle ?? "") | Keywords: \(item.keywords.prefix(8).joined(separator: ", "))"
        }.joined(separator: "\n")
        let actions = ActionRegistry.shared.descriptors.map {
            "ID: \($0.id) | Name: \($0.title) | Required parameters: \($0.requiredParameters.sorted().joined(separator: ", ")) | Confirmation: \($0.requiresConfirmation)"
        }.joined(separator: "\n")
        let prompt = """
        The user wants to: <user-intent>\(query)</user-intent>
        Select a target only from the candidates and an action only from the registry. Never invent identifiers.
        Return parameters needed by the action and list any required values that are not safely inferable.
        Rank recommendations by how directly they accomplish the intent. Return an empty list when none fit.
        Keep each reason factual and concise.
        <candidates>
        \(candidateText)
        </candidates>
        <action-registry>
        \(actions)
        </action-registry>
        """
        do {
            let response = try await LanguageModelSession().respond(to: prompt, generating: GeneratedIntentResponse.self)
            let generated = response.content.matches.map { match in
                IntentRecommendation(targetIdentifier: match.targetIdentifier,
                                     actionIdentifier: match.actionIdentifier,
                                     parameters: Dictionary(match.parameters.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first }),
                                     missingParameters: match.missingParameters,
                                     confidence: Double(match.confidence) / 100,
                                     reason: match.reason,
                                     requiresConfirmation: match.requiresConfirmation)
            }
            return IntentRecommendationValidator.validate(generated,
                allowedTargets: Set(candidates.map(\.id)), allowedActions: ActionRegistry.shared.identifiers)
        } catch {
            logger.error("Intent search failed: \(error.localizedDescription)")
            throw error
        }
    }
}
