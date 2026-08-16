import Foundation
import Testing
@testable import LaunchDeckCore

struct SearchRankingTests {
    private func makeApp(identifier: String, name: String? = nil, isSystemApp: Bool = false) -> DiscoveredApp {
        DiscoveredApp(name: name ?? identifier,
                      bundleIdentifier: identifier,
                      path: "/Applications/\(name ?? identifier).app",
                      category: nil,
                      bundleVersion: nil,
                      developer: nil,
                      isSystemApp: isSystemApp,
                      keywords: [])
    }

    private func makeRecent(identifier: String, launchCount: Int = 1) -> RecentLaunch {
        RecentLaunch(identifier: identifier,
                     displayName: identifier,
                     path: "/Applications/\(identifier).app",
                     lastLaunch: Date(),
                     launchCount: launchCount)
    }

    @Test("Favorites outrank the most recently launched app")
    func favoriteWeightBeatsRecents() {
        let favorite = makeApp(identifier: "com.test.favorite")
        let recent = makeApp(identifier: "com.test.recent")
        let layout: [AppCollectionItem] = [.app(favorite.identifier), .app(recent.identifier)]
        let favorites: Set<String> = [favorite.identifier]
        let recents = [makeRecent(identifier: recent.identifier)]

        let favoriteRank = SearchRanking.rank(for: favorite, favorites: favorites, recents: recents, layout: layout)
        let recentRank = SearchRanking.rank(for: recent, favorites: favorites, recents: recents, layout: layout)
        #expect(favoriteRank > recentRank)
        #expect(favoriteRank - recentRank == 20 - 10 + 1) // favorite also wins layout position (index 0 vs 1)
    }

    @Test("Layout position contributes up to 15 points and floors at zero")
    func layoutPositionWeight() {
        let apps = (0..<20).map { makeApp(identifier: "com.test.app\($0)") }
        let layout = apps.map { AppCollectionItem.app($0.identifier) }

        let first = SearchRanking.rank(for: apps[0], favorites: [], recents: [], layout: layout)
        let fifteenth = SearchRanking.rank(for: apps[14], favorites: [], recents: [], layout: layout)
        let twentieth = SearchRanking.rank(for: apps[19], favorites: [], recents: [], layout: layout)

        #expect(first - fifteenth == 14)
        #expect(twentieth == 1) // layout floor 0 + non-system 1
        #expect(first == 15 + 1)
    }

    @Test("System apps lose the non-system bonus")
    func systemAppWeight() {
        let system = makeApp(identifier: "com.apple.system", isSystemApp: true)
        let thirdParty = makeApp(identifier: "com.test.thirdparty")
        #expect(SearchRanking.rank(for: system, favorites: [], recents: [], layout: []) == 0)
        #expect(SearchRanking.rank(for: thirdParty, favorites: [], recents: [], layout: []) == 1)
    }

    @Test("Filter matches searchable text case-insensitively and sorts by rank")
    func filterMatching() {
        let safari = DiscoveredApp(name: "Safari",
                                   bundleIdentifier: "com.apple.Safari",
                                   path: "/Applications/Safari.app",
                                   category: "Utilities",
                                   bundleVersion: nil,
                                   developer: "Apple",
                                   isSystemApp: true,
                                   keywords: ["browser"])
        let editor = makeApp(identifier: "com.test.editor", name: "Photo Editor")
        let unrelated = makeApp(identifier: "com.test.calc", name: "Calculator")

        let matches = SearchRanking.filter([safari, editor, unrelated], matching: "edit",
                                           favorites: [], recents: [], layout: [])
        #expect(matches.map(\.identifier) == [editor.identifier])

        let favorites: Set<String> = [safari.identifier]
        let ranked = SearchRanking.filter([safari, editor], matching: "a",
                                          favorites: favorites, recents: [], layout: [])
        #expect(ranked.first?.identifier == safari.identifier)
    }
}
