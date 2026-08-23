import Testing
@testable import LaunchDeckCore

@Suite("Qualified search query")
struct SearchQueryTests {
    private let items = [
        SearchItem(id: "a", kind: .application, title: "Xcode", target: .application(identifier: "xcode", path: "/Applications/Xcode.app")),
        SearchItem(id: "b", kind: .file, title: "Launch Plan", target: .file(path: "/Users/me/Documents/Launch Plan.pdf")),
        SearchItem(id: "c", kind: .file, title: "Notes", target: .file(path: "/Users/me/Desktop/Notes.md")),
    ]

    @Test func parsesAliasesQuotesAndFreeText() {
        let query = SearchQuery.parse("kind:files path:\"Documents\" ext:pdf launch")
        #expect(query.text == "launch")
        #expect(query.filters.count == 3)
        #expect(query.matches(items[1]))
        #expect(!query.matches(items[2]))
    }

    @Test func appQualifierNarrowsAndSearchesByName() {
        let results = UnifiedSearchIndex(items: items).search(SearchQuery.parse("app:xco"))
        #expect(results.map(\.item.id) == ["a"])
    }

    @Test func filterOnlyQueryReturnsAlphabetizedMatches() {
        let results = UnifiedSearchIndex(items: items).search(SearchQuery.parse("ext:md"))
        #expect(results.map(\.item.id) == ["c"])
    }
}
