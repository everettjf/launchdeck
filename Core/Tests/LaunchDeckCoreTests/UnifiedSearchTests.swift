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
}
