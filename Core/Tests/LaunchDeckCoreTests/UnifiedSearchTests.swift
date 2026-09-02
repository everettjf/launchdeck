import Foundation
import Testing
@testable import LaunchDeckCore

struct UnifiedSearchTests {
    @Test("Unified search ranks exact titles and searches across kinds")
    func mixedKinds() {
        let items = [
            SearchItem(id: "app:code", kind: .application, title: "Code", target: .application(identifier: "code", path: "/Code.app")),
            SearchItem(id: "project:deck", kind: .project, title: "LaunchDeck", keywords: ["swift"], target: .project(path: "/LaunchDeck.xcodeproj")),
            SearchItem(id: "recipe:pdf", kind: .recipe, title: "Export PDF", target: .recipe(identifier: UUID())),
        ]
        let index = UnifiedSearchIndex(items: items)
        #expect(index.search("launchdeck").first?.item.kind == .project)
        #expect(index.search("pdf").first?.item.kind == .recipe)
        #expect(index.search("swift").first?.item.id == "project:deck")
    }

    @Test("Intent 2 validator rejects invented targets and actions")
    func validatesIntentRecommendations() {
        let valid = IntentRecommendation(targetIdentifier: "target", actionIdentifier: "open.project", confidence: 0.7, reason: "Fits", requiresConfirmation: false)
        let inventedTarget = IntentRecommendation(targetIdentifier: "invented", actionIdentifier: "open.project", confidence: 1, reason: "Bad", requiresConfirmation: false)
        let inventedAction = IntentRecommendation(targetIdentifier: "target", actionIdentifier: "shell.anything", confidence: 1, reason: "Bad", requiresConfirmation: true)
        let result = IntentRecommendationValidator.validate([inventedTarget, inventedAction, valid], allowedTargets: ["target"], allowedActions: ["open.project"])
        #expect(result == [valid])
    }

    @Test("Per-item learning boosts can change ranking without changing text matching")
    func itemBoosts() {
        let first = SearchItem(id: "first", kind: .application, title: "Code One",
                               target: .application(identifier: "one", path: "/One.app"))
        let second = SearchItem(id: "second", kind: .application, title: "Code Two",
                                target: .application(identifier: "two", path: "/Two.app"))
        let results = UnifiedSearchIndex(items: [first, second]).search("code", itemBoosts: ["second": 0.2])
        #expect(results.first?.item.id == "second")
    }

    @Test("Token narrowing preserves metadata matches and typo fallback")
    func tokenNarrowingPreservesBehavior() {
        let items = [
            SearchItem(id: "exact", kind: .application, title: "Benchmark App 50",
                       target: .application(identifier: "exact", path: "/Exact.app")),
            SearchItem(id: "other", kind: .file, title: "Brief 50", target: .file(path: "/Brief")),
        ]
        let index = UnifiedSearchIndex(items: items)
        #expect(index.search("benchmark app 50").first?.item.id == "exact")
        #expect(index.search("benchmrk app 50").first?.item.id == "exact")
        #expect(index.search("b").contains { $0.item.id == "exact" })
        #expect(index.search("benc").first?.item.id == "exact")
    }

    @Test("Qualified multi-token search narrows candidates without changing filters")
    func qualifiedTokenNarrowingPreservesFilters() {
        let items = [
            SearchItem(id: "app", kind: .application, title: "Quarterly Brief 50",
                       target: .application(identifier: "brief", path: "/Brief.app")),
            SearchItem(id: "pdf", kind: .file, title: "Quarterly Brief 50", keywords: ["report"],
                       target: .file(path: "/Documents/Quarterly Brief 50.pdf")),
            SearchItem(id: "wrong-extension", kind: .file, title: "Quarterly Brief 50",
                       target: .file(path: "/Documents/Quarterly Brief 50.txt")),
        ]
        let index = UnifiedSearchIndex(items: items)
        let result = index.search(SearchQuery.parse("kind:file ext:pdf quarterly brief 50"))
        #expect(result.map(\.item.id) == ["pdf"])
    }
}
