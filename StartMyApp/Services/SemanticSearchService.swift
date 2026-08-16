import Foundation
import FoundationModels
import OSLog
import LaunchDeckCore

private nonisolated let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "StartMyApp", category: "SemanticSearch")

// Define the output structure using @Generable
@Generable
struct AppMatch {
    var appIndex: Int
    var score: Int  // 0-100
    var reason: String
}

@Generable
struct AppSearchResult {
    var matches: [AppMatch]
}

actor SemanticSearchService {
    private var model = SystemLanguageModel.default
    private var isAvailable: Bool = false

    init() async {
        // Check if Foundation Models is available using SystemLanguageModel
        switch model.availability {
        case .available:
            self.isAvailable = true
        case .unavailable:
            self.isAvailable = false
        }
    }

    func searchApps(_ apps: [DiscoveredApp], query: String) async -> [(app: DiscoveredApp, score: Double)] {
        guard isAvailable else {
            return []
        }

        // Strategy: Use concurrent batch scoring for better accuracy and speed
        let batchSize = 50
        let batches = stride(from: 0, to: min(apps.count, 60), by: batchSize).map { start in
            Array(apps[start..<min(start + batchSize, apps.count)])
        }

        var allResults: [(app: DiscoveredApp, score: Double)] = []

        // Process batches concurrently
        await withTaskGroup(of: [(app: DiscoveredApp, score: Double)].self) { group in
            for (batchIndex, batch) in batches.enumerated() {
                group.addTask {
                    await self.scoreBatch(batch, query: query, batchIndex: batchIndex)
                }
            }

            for await batchResults in group {
                allResults.append(contentsOf: batchResults)
            }
        }

        // Sort by score and return top results
        let sortedResults = allResults
            .sorted { $0.score > $1.score }
            .filter { $0.score > 0.3 }
            .prefix(15)

        return Array(sortedResults)
    }

    private func scoreBatch(_ apps: [DiscoveredApp], query: String, batchIndex: Int) async -> [(app: DiscoveredApp, score: Double)] {
        // Build app list for this batch
        let appsList = apps.enumerated().map { index, app in
            let cat = app.category ?? "Utility"
            let dev = app.developer ?? "Unknown"
            return "Index \(index + 1): \(app.name) (\(cat)) by \(dev)"
        }.joined(separator: "\n")

        let instructions = """
        Find macOS applications that match the search query: "\(query)"

        Available applications:
        \(appsList)

        For each matching app, return:
        - appIndex: the index number (1-based)
        - score: relevance score from 0-100
        - reason: brief explanation why it matches

        Consider:
        - Name similarity to query
        - Category relevance (e.g., "good" → productivity/utility apps)
        - Common use cases
        - Developer reputation

        Only include apps with score > 30.
        """

        do {
            // Create a LanguageModelSession for the AI call
            let session = LanguageModelSession()

            // Use guided generation to get structured output
            let response = try await session.respond(
                to: instructions,
                generating: AppSearchResult.self
            )

            let result = response.content

            // Convert to our result format
            var results: [(app: DiscoveredApp, score: Double)] = []
            for match in result.matches {
                let index = match.appIndex - 1
                guard index >= 0 && index < apps.count else {
                    continue
                }
                let normalizedScore = Double(match.score) / 100.0
                results.append((apps[index], normalizedScore))
            }

            return results

        } catch {
            logger.error("Semantic search batch \(batchIndex) failed: \(error.localizedDescription)")
            return []
        }
    }
}
