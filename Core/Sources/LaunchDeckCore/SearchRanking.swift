import Foundation

/// Keyword filtering and ranking for the search field.
///
/// Ranking weights (higher sorts first):
/// - favorite: +20
/// - most recently launched app: +10
/// - layout position: +max(0, 15 - index)
/// - non-system app: +1
public enum SearchRanking {
    public static func rank(for app: DiscoveredApp,
                            favorites: Set<String>,
                            recents: [RecentLaunch],
                            layout: [AppCollectionItem]) -> Int {
        var weight = 0
        if favorites.contains(app.identifier) {
            weight += 20
        }
        if let firstRecent = recents.first, firstRecent.identifier == app.identifier {
            weight += 10
        }
        if let layoutIndex = layout.firstIndex(where: { $0.containedAppIdentifiers.contains(app.identifier) }) {
            weight += max(0, 15 - layoutIndex)
        }
        if !app.isSystemApp {
            weight += 1
        }
        return weight
    }

    public static func filter(_ apps: [DiscoveredApp],
                              matching query: String,
                              favorites: Set<String>,
                              recents: [RecentLaunch],
                              layout: [AppCollectionItem]) -> [DiscoveredApp] {
        SearchIndex(apps: apps)
            .search(query, favorites: favorites, recents: recents, layout: layout)
            .map(\.app)
    }
}
