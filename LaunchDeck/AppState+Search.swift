import AppKit
import Combine
import Foundation
import LaunchDeckCore
import SwiftUI

/// Local, unified and intent search queries.
extension AppState {
    func appsMatchingSearch() -> [DiscoveredApp] {
        // This is now a pure function without side effects
        guard !searchQuery.isEmpty else {
            return allApps()
        }

        // Check if using AI search
        let useAISearch = searchQuery.hasPrefix("/")
        let actualQuery = useAISearch ? String(searchQuery.dropFirst()) : searchQuery

        // If only "/" is entered, return empty
        if useAISearch && actualQuery.isEmpty {
            return []
        }

        return localRankedResults(for: actualQuery).map(\.app)
    }

    /// Ranks the unified index off the main actor; the small utility, clipboard and extension
    /// providers stay on the main actor because they read main-actor stores.
    func searchItems(matching query: String, limit: Int = 80) async -> [SearchItem] {
        let parsed = SearchQuery.parse(query)
        let searchableText = parsed.text
        let utilityCandidates = searchableText.isEmpty ? [] : (UtilitySearchProvider.results(for: searchableText, quicklinks: quicklinkStore.quicklinks)
            + DesktopSearchProvider.items(matching: searchableText,
                                          clipboardEnabled: preferences.clipboardEnabled,
                                          clipboardEntries: clipboardStore.entries,
                                          snippets: snippetStore.snippets,
                                          // {clipboard} means the live clipboard, not the newest history entry.
                                          clipboardText: NSPasteboard.general.string(forType: .string))
            + extensionStore.searchItems(matching: searchableText))
        let utilities = utilityCandidates.filter(parsed.matches)
        let index = unifiedIndex.index
        let itemBoosts = searchLearningStore.boosts(for: parsed.text)
        let ranked = await Task.detached(priority: .userInitiated) {
            index.search(parsed, kindBoosts: [.application: 0.04, .project: 0.03],
                         itemBoosts: itemBoosts, limit: limit).map(\.item)
        }.value
        return Array((utilities + ranked).prefix(limit))
    }

    func searchItem(identifier: String) -> SearchItem? { unifiedIndex.item(identifier: identifier) }

    func intentReason(for app: DiscoveredApp) -> String? {
        intentResults.first { $0.targetIdentifier == "application:\(app.identifier)" }?.reason
    }

    func intentDetail(for item: SearchItem) -> String? {
        guard let result = intentResults.first(where: { $0.targetIdentifier == item.id }) else { return nil }
        let percent = Int((result.confidence * 100).rounded())
        let actionName = ActionRegistry.shared.descriptors.first { $0.id == result.actionIdentifier }?.title
            ?? result.actionIdentifier
        let appName: String?
        if case .application(let identifier, _) = item.target { appName = appsByIdentifier[identifier]?.name }
        else { appName = nil }
        let resolution = IntentActionResolver.resolve(result, target: item, applicationName: appName,
                                                      installedApplications: appsByIdentifier.mapValues { $0.name },
                                                      recipes: recipeStore.recipes)
        let missing: String
        if case .missingParameters(let values) = resolution { missing = " · Needs \(values.joined(separator: ", "))" }
        else if case .unresolved = resolution { missing = " · Unresolved" }
        else { missing = "" }
        return "\(result.reason) · \(percent)% · \(actionName)\(missing)"
    }

    private func localRankedResults(for query: String, limit: Int? = nil) -> [(app: DiscoveredApp, score: Double)] {
        searchIndex.search(query, favorites: favorites, recents: recents,
                           layout: layout, limit: limit)
    }
}
