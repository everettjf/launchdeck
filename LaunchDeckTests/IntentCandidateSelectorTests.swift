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
}
