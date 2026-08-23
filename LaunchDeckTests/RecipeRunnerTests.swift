import XCTest
@testable import LaunchDeck

@MainActor
final class RecipeRunnerTests: XCTestCase {
    func testRunsStepsInOrder() async {
        let steps: [RecipeStep] = [.openProject(path: "/one"), .openTerminal(directory: "/two"), .runShortcut(name: "Three")]
        var visited: [UUID] = []
        let succeeded = await RecipeRunner.run(steps) { step in visited.append(step.id); return true }
        XCTAssertTrue(succeeded)
        XCTAssertEqual(visited, steps.map(\.id))
    }

    func testStopsAtFirstFailure() async {
        let steps: [RecipeStep] = [.openProject(path: "/one"), .openTerminal(directory: "/two"), .runShortcut(name: "Three")]
        var visited: [UUID] = []
        let succeeded = await RecipeRunner.run(steps) { step in
            visited.append(step.id)
            return visited.count < 2
        }
        XCTAssertFalse(succeeded)
        XCTAssertEqual(visited, Array(steps.prefix(2).map(\.id)))
    }

    func testContinuePolicyRunsFollowingSteps() async {
        let first = RecipeStep(operation: .openTerminal(directory: "/missing"), failurePolicy: .continueNext)
        let second = RecipeStep.openProject(path: "/tmp")
        var executed: [UUID] = []
        let result = await RecipeRunner.run([first, second]) { step in
            executed.append(step.id)
            return step.id == second.id
        }
        XCTAssertFalse(result)
        XCTAssertEqual(executed, [first.id, second.id])
    }
}
