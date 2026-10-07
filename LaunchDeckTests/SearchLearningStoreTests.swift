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

    func testBoundsLearnedQueriesAndItemsPerQuery() {
        let suite = "SearchLearningBounds.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SearchLearningStore(defaults: defaults, maximumQueries: 3, maximumItemsPerQuery: 2)
        for query in ["a", "b", "c", "d"] { store.record(query: query, itemID: "app:\(query)") }
        XCTAssertEqual(Set(store.snapshot.selections.keys), ["b", "c", "d"])
        store.record(query: "x", itemID: "one")
        store.record(query: "x", itemID: "one")
        store.record(query: "x", itemID: "two")
        store.record(query: "x", itemID: "three")
        XCTAssertEqual(store.snapshot.selections["x"], ["one": 2, "three": 1])
        let reloaded = SearchLearningStore(defaults: defaults, maximumQueries: 3, maximumItemsPerQuery: 2)
        XCTAssertEqual(reloaded.snapshot, store.snapshot)
    }

    func testDecodesSnapshotsWrittenBeforeSelectionOrderExisted() throws {
        let legacy = #"{"selections":{"code":{"app:code":2}},"recentQueries":["code"]}"#
        let snapshot = try JSONDecoder().decode(SearchLearningSnapshot.self, from: Data(legacy.utf8))
        XCTAssertEqual(snapshot.selectionOrder, ["code"])
        XCTAssertEqual(snapshot.selections["code"], ["app:code": 2])
    }
}
