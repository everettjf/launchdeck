import XCTest
@testable import LaunchDeck
import LaunchDeckCore

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

    func testLaunchCountsOutliveTheRecentsListAndExpire() {
        let suite = "LaunchCounts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSince1970: 1_000_000)
        let seed = [RecentLaunch(identifier: "editor", displayName: "Editor", path: "/E.app", lastLaunch: start, launchCount: 40)]
        let store = LaunchCountStore(defaults: defaults, retention: 100 * 24 * 3600, seedingFrom: seed, now: start)
        for index in 0..<20 { store.recordLaunch(of: "app\(index)", at: start.addingTimeInterval(Double(index))) }
        store.recordLaunch(of: "editor", at: start.addingTimeInterval(60))
        XCTAssertEqual(store.counts["editor"], 41)

        let reloaded = LaunchCountStore(defaults: defaults, retention: 100 * 24 * 3600, now: start.addingTimeInterval(120))
        XCTAssertEqual(reloaded.counts["editor"], 41)
        let later = LaunchCountStore(defaults: defaults, retention: 100 * 24 * 3600, now: start.addingTimeInterval(101 * 24 * 3600))
        XCTAssertTrue(later.counts.isEmpty)
        later.clear()
        XCTAssertNil(defaults.data(forKey: "launcher.launchCounts.v1"))
    }
}
