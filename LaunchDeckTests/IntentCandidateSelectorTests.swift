import XCTest
import LaunchDeckCore
@testable import LaunchDeck

final class IntentCandidateSelectorTests: XCTestCase {
    func testSemanticCandidatesIncludeFallbackWhenTextDoesNotMatch() {
        let app = SearchItem(id: "application:editor", kind: .application, title: "Pixelmator",
                             keywords: ["photo"], target: .application(identifier: "editor", path: "/Pixelmator.app"))
        let project = SearchItem(id: "project:deck", kind: .project, title: "LaunchDeck",
                                 target: .project(path: "/LaunchDeck.xcodeproj"))
        let catalog = Dictionary(uniqueKeysWithValues: [app, project].map { ($0.id, $0) })
        let result = IntentCandidateSelector.select(query: "make something beautiful",
                                                    index: UnifiedSearchIndex(items: [app, project]),
                                                    catalog: catalog,
                                                    preferredFallbackIdentifiers: [app.id, project.id])
        XCTAssertEqual(result.map(\.id), [app.id, project.id])
        XCTAssertEqual(result.map(\.localScore), [0, 0])
    }

    func testTextMatchesRemainAheadOfFallback() {
        let app = SearchItem(id: "application:editor", kind: .application, title: "Pixelmator",
                             target: .application(identifier: "editor", path: "/Pixelmator.app"))
        let project = SearchItem(id: "project:deck", kind: .project, title: "LaunchDeck",
                                 target: .project(path: "/LaunchDeck.xcodeproj"))
        let catalog = Dictionary(uniqueKeysWithValues: [app, project].map { ($0.id, $0) })
        let result = IntentCandidateSelector.select(query: "launchdeck", index: UnifiedSearchIndex(items: [app, project]),
                                                    catalog: catalog, preferredFallbackIdentifiers: [app.id])
        XCTAssertEqual(result.first?.id, project.id)
        XCTAssertGreaterThan(result.first?.localScore ?? 0, 0)
    }

    func testCandidateCountIsBoundedForTheContextWindow() {
        let items = (0..<100).map { index in
            SearchItem(id: "file:/docs/\(index)", kind: .file, title: "Note \(index)", target: .file(path: "/docs/\(index)"))
        }
        let catalog = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let result = IntentCandidateSelector.select(query: "unrelated words", index: UnifiedSearchIndex(items: items),
                                                    catalog: catalog, preferredFallbackIdentifiers: [])
        XCTAssertEqual(result.count, IntentCandidateSelector.defaultLimit)
        XCTAssertEqual(Set(result.map(\.id)).count, result.count)
    }

    @available(macOS 26.0, *)
    func testCandidatePromptLinesStayShort() {
        let item = SearchItem(id: "file:/x", kind: .file, title: String(repeating: "Long title ", count: 20),
                              subtitle: "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/Projects/2026/Reports",
                              keywords: ["a", "b", "c", "d", "e", "f", "g", "h"], target: .file(path: "/x"))
        let line = FoundationModelsIntentSearcher.candidateLine(item)
        XCTAssertTrue(line.contains("…/2026/Reports"))
        XCTAssertFalse(line.contains("e, f"))
        XCTAssertLessThan(line.count, 220)
    }
}
