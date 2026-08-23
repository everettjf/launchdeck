import XCTest
import LaunchDeckCore
@testable import LaunchDeck

@MainActor
private final class MockIntentSearcher: IntentSearching {
    let state: IntentSearchAvailability
    let result: [IntentRecommendation]
    let delay: Duration
    init(state: IntentSearchAvailability, result: [IntentRecommendation] = [], delay: Duration = .zero) {
        self.state = state
        self.result = result
        self.delay = delay
    }
    func availability() -> IntentSearchAvailability { state }
    func search(query: String, candidates: [SearchItemCandidate]) async throws -> [IntentRecommendation] {
        try await Task.sleep(for: delay)
        return result
    }
}

@MainActor
final class IntentSearchControllerTests: XCTestCase {
    func testUnavailableSearcherNeverClaimsAvailability() async {
        let controller = SemanticSearchController(
            searcher: MockIntentSearcher(state: .unavailable(.requiresMacOS26))
        )
        controller.initialize()
        await Task.yield()
        XCTAssertEqual(controller.availability, .unavailable(.requiresMacOS26))
        XCTAssertFalse(controller.isAvailable)
    }

    func testNonIntentQueryResetsResultsAndPhase() {
        let controller = SemanticSearchController(searcher: MockIntentSearcher(state: .available))
        controller.handleQueryChange("Safari")
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertTrue(controller.results.isEmpty)
    }

    func testIntentResultCompletesAndPreservesStructuredReason() async throws {
        let expected = IntentRecommendation(targetIdentifier: "application:app", actionIdentifier: "open.application",
                                            confidence: 0.9, reason: "Matches image editing", requiresConfirmation: false)
        let controller = SemanticSearchController(
            searcher: MockIntentSearcher(state: .available, result: [expected]),
            debounce: .zero,
            timeout: .seconds(1)
        )
        controller.candidatesProvider = { _ in [] }
        controller.initialize()
        await Task.yield()
        controller.handleQueryChange("/edit an image")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(controller.phase, .completed)
        XCTAssertEqual(controller.results, [expected])
    }

    func testNewQueryCancelsStaleRequest() async throws {
        let stale = IntentRecommendation(targetIdentifier: "application:stale", actionIdentifier: "open.application",
                                         confidence: 1, reason: "Old", requiresConfirmation: false)
        let controller = SemanticSearchController(
            searcher: MockIntentSearcher(state: .available, result: [stale], delay: .milliseconds(80)),
            debounce: .zero,
            timeout: .seconds(1)
        )
        controller.initialize()
        await Task.yield()
        controller.handleQueryChange("/old")
        await Task.yield()
        controller.handleQueryChange("new local query")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertTrue(controller.results.isEmpty)
    }
}
