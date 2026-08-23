import XCTest
@testable import LaunchDeck

final class WorkflowSchemaV2Tests: XCTestCase {
    func testV1MigrationPreservesEveryOperationAndStableIDs() throws {
        let steps = [
            RecipeStep.openApplication(identifier: "com.apple.TextEdit", name: "TextEdit"),
            RecipeStep.openProject(path: "/tmp/project"),
            RecipeStep.openTerminal(directory: "/tmp"),
            RecipeStep.runShortcut(name: "Archive"),
            RecipeStep.delay(seconds: 0.1),
            RecipeStep.objectAction(.move, sources: ["/tmp/a"], target: "/tmp/b")
        ]
        let recipe = Recipe(name: "Legacy", steps: steps)
        let workflow = recipe.resolvedWorkflow
        XCTAssertEqual(workflow.schemaVersion, 2)
        XCTAssertEqual(workflow.nodes.map(\.id), steps.map(\.id))
        XCTAssertEqual(workflow.nodes.map(\.kindIdentifier), ["action.open-application", "action.open", "action.open-terminal", "action.run-shortcut", "logic.delay", "action.move"])
        XCTAssertEqual(workflow.edges.count, steps.count - 1)
        XCTAssertTrue(WorkflowValidator.validate(workflow).filter { $0.severity == .error }.isEmpty)
        let roundTrip = try JSONDecoder().decode(WorkflowDefinition.self, from: JSONEncoder().encode(workflow))
        XCTAssertEqual(roundTrip, workflow)
    }

    func testTypeMismatchAndCycleAreRejected() {
        let text = WorkflowNode(kindIdentifier: "data.text", configuration: ["value": .text("hello")])
        let move = WorkflowNode(kindIdentifier: "action.move", configuration: ["objects": .collection([.file("/tmp/a")])])
        let bad = WorkflowEdge(sourceNodeID: text.id, sourcePortID: "value", targetNodeID: move.id, targetPortID: "target")
        var workflow = WorkflowDefinition(name: "Bad", nodes: [text, move], edges: [bad])
        XCTAssertTrue(WorkflowValidator.validate(workflow).contains { $0.id.hasSuffix(".type") })
        workflow.edges = [
            .init(sourceNodeID: text.id, sourcePortID: "control", targetNodeID: move.id, targetPortID: "control"),
            .init(sourceNodeID: move.id, sourcePortID: "control", targetNodeID: text.id, targetPortID: "control")
        ]
        XCTAssertTrue(WorkflowValidator.validate(workflow).contains { $0.id == "workflow.cycle" })
    }

    func testCatalogIdentifiersAreUnique() {
        XCTAssertEqual(Set(WorkflowNodeCatalog.definitions.map(\.id)).count, WorkflowNodeCatalog.definitions.count)
    }

    func testDuplicateNodeIDsReportAnErrorWithoutCrashing() {
        let id = UUID()
        let workflow = WorkflowDefinition(name: "Duplicate", nodes: [
            WorkflowNode(id: id, kindIdentifier: "data.text"),
            WorkflowNode(id: id, kindIdentifier: "data.text")
        ])
        XCTAssertTrue(WorkflowValidator.validate(workflow).contains { $0.id == "workflow.duplicate-node" })
    }
}

@MainActor
final class RecipeStudioStoreTests: XCTestCase {
    func testOutlineEditingUndoAndTypedConnect() {
        let studio = RecipeStudioStore()
        studio.add(WorkflowNodeCatalog.definition(for: "data.text")!)
        studio.add(WorkflowNodeCatalog.definition(for: "output.copy")!)
        let source = studio.workflow.nodes[0]
        let target = studio.workflow.nodes[1]
        studio.connect(sourceNodeID: source.id, sourcePortID: "value", targetNodeID: target.id, targetPortID: "value")
        XCTAssertEqual(studio.workflow.edges.filter { $0.targetPortID == "value" }.count, 1)
        studio.removeSelection()
        XCTAssertEqual(studio.workflow.nodes.count, 1)
        studio.undo()
        XCTAssertEqual(studio.workflow.nodes.count, 2)
    }

    func testAutomaticLayoutHandlesLargeWorkflow() {
        let nodes = (0..<1_000).map { WorkflowNode(kindIdentifier: "data.text", position: .init(x: 0, y: Double($0))) }
        measure { _ = WorkflowGraphEditor.automaticLayout(WorkflowDefinition(name: "Large", nodes: nodes)) }
    }
}

@MainActor
final class WorkflowExecutionEngineTests: XCTestCase {
    final class FakeExecutor: WorkflowNodeExecuting {
        var executed: [UUID] = []
        func execute(node: WorkflowNode, inputs: [String: WorkflowValue], workflow: WorkflowDefinition) async throws -> WorkflowNodeExecutionResult {
            executed.append(node.id)
            return .init(outputs: ["control": .none, "value": .text("done")], route: .deterministic, undoOperation: nil)
        }
    }

    func testEngineUsesTopologicalOrderAndPersistsReceipt() async {
        let first = WorkflowNode(kindIdentifier: "data.text", configuration: ["value": .text("a")])
        let second = WorkflowNode(kindIdentifier: "output.copy", configuration: ["value": .text("a")])
        let workflow = WorkflowDefinition(name: "Run", nodes: [second, first], edges: [
            .init(sourceNodeID: first.id, sourcePortID: "control", targetNodeID: second.id, targetPortID: "control")
        ])
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        let store = WorkflowReceiptStore(defaults: suite)
        let executor = FakeExecutor()
        let engine = WorkflowExecutionEngine(executor: executor, receiptStore: store)
        let receipt = await engine.run(workflow)
        XCTAssertTrue(receipt.succeeded)
        XCTAssertEqual(executor.executed, [first.id, second.id])
        XCTAssertEqual(store.receipts.first?.id, receipt.id)
    }
}
