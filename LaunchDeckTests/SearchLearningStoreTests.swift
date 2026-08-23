import XCTest
@testable import LaunchDeck

@MainActor
final class SearchLearningStoreTests: XCTestCase {
    func testLearnsPerQueryPersistsRecentQueriesAndClears() {
        let suite = "SearchLearningStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SearchLearningStore(defaults: defaults)
        store.record(query: " Code ", itemID: "app:code")
        store.record(query: "code", itemID: "app:code")
        XCTAssertGreaterThan(store.boosts(for: "CODE")["app:code"] ?? 0, 0)
        XCTAssertEqual(store.snapshot.recentQueries, ["code"])
        store.clear()
        XCTAssertTrue(store.snapshot.selections.isEmpty)
    }
}
