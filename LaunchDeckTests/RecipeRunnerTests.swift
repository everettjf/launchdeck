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

    func testRetriesOptionalFailuresAndRecordsAttempts() async {
        let retry = RecipeStep(operation: .openProject(path: "/tmp"), retryCount: 2)
        let optional = RecipeStep(operation: .runShortcut(name: "Optional"), isOptional: true)
        var attempts = 0
        let report = await RecipeRunner.runDetailed([retry, optional]) { step in
            if step.id == retry.id { attempts += 1; return attempts == 3 }
            return false
        }
        XCTAssertTrue(report.succeeded)
        XCTAssertEqual(report.stepLogs.map(\.attempts), [3, 1])
        XCTAssertEqual(report.stepLogs.last?.outcome, "optional-failure")
    }

    func testOutputVariablesResolveInFollowingStepsAndConditionCanSkip() async {
        let first = RecipeStep(operation: .openProject(path: "/tmp/project"), outputVariable: "project")
        let second = RecipeStep(operation: .openTerminal(directory: "{{project}}"))
        let skipped = RecipeStep(operation: .runShortcut(name: "Never"),
                                 condition: .valueEquals(lhs: "a", rhs: "b"))
        var operations: [RecipeStep.Operation] = []
        let report = await RecipeRunner.runDetailed([first, second, skipped]) { step in
            operations.append(step.operation); return true
        }
        XCTAssertTrue(report.succeeded)
        XCTAssertEqual(operations, [.openProject(path: "/tmp/project"), .openTerminal(directory: "/tmp/project")])
        XCTAssertEqual(report.stepLogs.last?.outcome, "skipped")
    }
}
