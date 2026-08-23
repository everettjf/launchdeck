import XCTest
import LaunchDeckCore
@testable import LaunchDeck

final class IntentActionResolverTests: XCTestCase {
    func testInfersSafeParametersFromConcreteTarget() {
        let item = SearchItem(id: "project:/tmp/deck", kind: .project, title: "Deck",
                              target: .project(path: "/tmp/deck"))
        let recommendation = IntentRecommendation(targetIdentifier: item.id, actionIdentifier: "open.terminal",
                                                  missingParameters: ["directory"], confidence: 0.9,
                                                  reason: "Work here", requiresConfirmation: true)
        XCTAssertEqual(IntentActionResolver.resolve(recommendation, target: item),
                       .action(.openTerminal(directory: "/tmp/deck")))
    }

    func testDoesNotSilentlyFallBackWhenParametersRemainMissing() {
        let item = SearchItem(id: "action:open.file-with", kind: .action, title: "Open File With Application",
                              target: .registeredAction(identifier: "open.file-with"))
        let recommendation = IntentRecommendation(targetIdentifier: item.id, actionIdentifier: "open.file-with",
                                                  confidence: 0.8, reason: "Needs targets", requiresConfirmation: false)
        XCTAssertEqual(IntentActionResolver.resolve(recommendation, target: item),
                       .missingParameters(["applicationIdentifier", "applicationName", "path"]))
    }

    func testRejectsInventedActionAtResolutionBoundary() {
        let item = SearchItem(id: "file:/tmp/a", kind: .file, title: "A", target: .file(path: "/tmp/a"))
        let recommendation = IntentRecommendation(targetIdentifier: item.id, actionIdentifier: "shell.execute",
                                                  confidence: 1, reason: "Unsafe", requiresConfirmation: true)
        XCTAssertEqual(IntentActionResolver.resolve(recommendation, target: item), .missingParameters(["unknownAction"]))
    }

    func testOpenFileWithRejectsInventedApplicationParameter() {
        let item = SearchItem(id: "file:/tmp/a", kind: .file, title: "A", target: .file(path: "/tmp/a"))
        let recommendation = IntentRecommendation(targetIdentifier: item.id, actionIdentifier: "open.file-with",
                                                  parameters: ["applicationIdentifier": "com.invented.app", "applicationName": "Invented"],
                                                  confidence: 0.9, reason: "Open it", requiresConfirmation: false)
        XCTAssertEqual(IntentActionResolver.resolve(recommendation, target: item,
                                                    installedApplications: ["com.real.app": "Real"]), .unresolved)
    }

    func testOpenFileWithUsesTrustedInstalledApplicationName() {
        let item = SearchItem(id: "file:/tmp/a", kind: .file, title: "A", target: .file(path: "/tmp/a"))
        let recommendation = IntentRecommendation(targetIdentifier: item.id, actionIdentifier: "open.file-with",
                                                  parameters: ["applicationIdentifier": "com.real.app", "applicationName": "Hallucinated"],
                                                  confidence: 0.9, reason: "Open it", requiresConfirmation: false)
        XCTAssertEqual(IntentActionResolver.resolve(recommendation, target: item,
                                                    installedApplications: ["com.real.app": "Real App"]),
                       .action(.openFile(path: "/tmp/a", applicationIdentifier: "com.real.app", applicationName: "Real App")))
    }
}
