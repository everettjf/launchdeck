import XCTest
@testable import LaunchDeck

@MainActor
final class ClipboardAndSnippetTests: XCTestCase {
    func testClipboardDeduplicatesLimitsExpiresAndClears() {
        let suite = "ClipboardStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ClipboardStore(defaults: defaults, maximumCount: 2)
        let now = Date()
        store.record("old", retentionHours: 24, now: now.addingTimeInterval(-90_000))
        store.record("one", retentionHours: 24, now: now)
        store.record("one", retentionHours: 24, now: now)
        store.record("two", retentionHours: 24, now: now)
        XCTAssertEqual(store.entries.map(\.text), ["two", "one"])
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testSnippetExpandsOnlyDeclaredLocalPlaceholders() {
        let snippet = Snippet(name: "Status", keyword: "status", content: "{date} {time} {clipboard}")
        let output = snippet.expanded(clipboard: "done", now: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(output.contains("done"))
        XCTAssertFalse(output.contains("{clipboard}"))
    }

    func testWindowCommandCatalogHasStableIdentifiers() {
        XCTAssertEqual(Set(DesktopWindowCommand.allCases.map(\.rawValue)).count, DesktopWindowCommand.allCases.count)
    }
}
