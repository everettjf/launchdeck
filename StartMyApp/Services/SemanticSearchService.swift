import Foundation
import FoundationModels

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
        print("🔍 Checking Foundation Models availability...")

        switch model.availability {
        case .available:
            self.isAvailable = true
            print("✅ Foundation Models ready for use")
        case .unavailable(.deviceNotEligible):
            self.isAvailable = false
            print("❌ Device not eligible for Apple Intelligence")
        case .unavailable(.appleIntelligenceNotEnabled):
            self.isAvailable = false
            print("⚠️ Apple Intelligence is not enabled. Please enable it in Settings.")
        case .unavailable(.modelNotReady):
            self.isAvailable = false
            print("⏳ Model is downloading or not ready")
        case .unavailable(let other):
            self.isAvailable = false
            print("❌ Model unavailable: \(other)")
        }
    }

    nonisolated static func isSemanticSearchAvailable() -> Bool {
        let model = SystemLanguageModel.default
        if case .available = model.availability {
            return true
        }
        return false
    }

    func searchApps(_ apps: [DiscoveredApp], query: String) async -> [(app: DiscoveredApp, score: Double)] {
        guard isAvailable else {
            print("      ❌ Semantic search unavailable")
            return []
        }

        print("\n      🤖 AI Search Starting")
        print("         Query: '\(query)'")
        print("         Total apps: \(apps.count)")

        let startTime = Date()

        // Strategy: Use concurrent batch scoring for better accuracy and speed
        let batchSize = 50
        let batches = stride(from: 0, to: min(apps.count, 60), by: batchSize).map { start in
            Array(apps[start..<min(start + batchSize, apps.count)])
        }

        print("         📦 Created \(batches.count) batches of ~\(batchSize) apps")

        var allResults: [(app: DiscoveredApp, score: Double)] = []

        // Process batches concurrently
        print("         ⚙️  Processing batches concurrently...")
        await withTaskGroup(of: [(app: DiscoveredApp, score: Double)].self) { group in
            for (batchIndex, batch) in batches.enumerated() {
                group.addTask {
                    await self.scoreBatch(batch, query: query, batchIndex: batchIndex)
                }
            }

            for await batchResults in group {
                allResults.append(contentsOf: batchResults)
                print("         ✓ Batch completed, total results so far: \(allResults.count)")
            }
        }

        // Sort by score and return top results
        let sortedResults = allResults
            .sorted { $0.score > $1.score }
            .filter { $0.score > 0.3 }
            .prefix(15)

        let duration = Date().timeIntervalSince(startTime)

        print("\n         ✅ AI Search Completed in \(String(format: "%.2f", duration))s")
        print("         📊 Found \(sortedResults.count) relevant apps:")
        for (index, result) in sortedResults.enumerated() {
            print("            \(index + 1). \(result.app.name) - score: \(String(format: "%.2f", result.score))")
        }
        print("")

        return Array(sortedResults)
    }

    private func scoreBatch(_ apps: [DiscoveredApp], query: String, batchIndex: Int) async -> [(app: DiscoveredApp, score: Double)] {
        print("            🔄 Batch \(batchIndex): Processing \(apps.count) apps...")

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

        print("            📤 Batch \(batchIndex): Sending to Foundation Models with guided generation...")

        do {
            // Create a LanguageModelSession for the AI call
            let session = LanguageModelSession()

            // Use guided generation to get structured output
            let response = try await session.respond(
                to: instructions,
                generating: AppSearchResult.self
            )

            let result = response.content

            print("            📥 Batch \(batchIndex): Got structured response with \(result.matches.count) matches")

            // Convert to our result format
            var results: [(app: DiscoveredApp, score: Double)] = []
            for match in result.matches {
                let index = match.appIndex - 1
                guard index >= 0 && index < apps.count else {
                    print("               ⚠️ Invalid index: \(match.appIndex)")
                    continue
                }
                let normalizedScore = Double(match.score) / 100.0
                results.append((apps[index], normalizedScore))
            }

            print("            ✅ Batch \(batchIndex): Parsed \(results.count) valid matches")
            for (app, score) in results.prefix(3) {
                let matchInfo = result.matches.first { match in
                    apps.firstIndex(where: { $0.bundleIdentifier == app.bundleIdentifier }).map { $0 + 1 } == match.appIndex
                }
                print("               • \(app.name): \(String(format: "%.0f", score * 100))% - \(matchInfo?.reason ?? "")")
            }

            return results

        } catch {
            print("            ❌ Batch \(batchIndex) error: \(error.localizedDescription)")
            return []
        }
    }

    private func calculateRelevance(query: String, app: DiscoveredApp) async -> Double {
        let prompt = """
        Rate how well this macOS application matches the search query. Respond with only a number between 0.0 and 1.0.

        Query: "\(query)"
        App: \(app.name)
        Category: \(app.category ?? "Unknown")
        Developer: \(app.developer ?? "Unknown")

        Score:
        """

        do {
            let content = try await FoundationModels.GeneratedContent(prompt)
            let text = content.jsonString
            let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            if let score = Double(trimmed) {
                return max(0.0, min(1.0, score))
            }
        } catch {
            print("Foundation Models error: \(error)")
        }

        return 0.0
    }

    private func buildAppDescription(_ app: DiscoveredApp) -> String {
        var parts: [String] = []

        parts.append("Name: \(app.name)")

        if let category = app.category {
            parts.append("Category: \(category)")
        }

        if let developer = app.developer {
            parts.append("Developer: \(developer)")
        }

        if let bundleId = app.bundleIdentifier {
            parts.append("Bundle ID: \(bundleId)")
        }

        if !app.keywords.isEmpty {
            parts.append("Keywords: \(app.keywords.joined(separator: ", "))")
        }

        return parts.joined(separator: "\n")
    }
}
