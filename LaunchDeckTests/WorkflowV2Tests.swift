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

    func testUnknownSourceCannotFlowIntoConcreteTypedPort() {
        XCTAssertFalse(WorkflowValueType.folder.accepts(.any))
        XCTAssertTrue(WorkflowValueType.any.accepts(.folder))
        XCTAssertTrue(WorkflowValueType.collection(.object).accepts(.collection(.file)))
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

    func testEarlierV2NodePayloadDecodesWithSafeDefaults() throws {
        let node = WorkflowNode(kindIdentifier: "data.text")
        var payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(node)) as! [String: Any]
        payload.removeValue(forKey: "condition")
        payload.removeValue(forKey: "isOptional")
        payload.removeValue(forKey: "outputVariable")
        let decoded = try JSONDecoder().decode(WorkflowNode.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertNil(decoded.condition)
        XCTAssertFalse(decoded.isOptional)
        XCTAssertNil(decoded.outputVariable)
    }

    func testToolAllowlistRejectsUnapprovedCapability() {
        var workflow = WorkflowDefinition(name: "Restricted", nodes: [
            WorkflowNode(kindIdentifier: "action.run-shortcut", configuration: ["shortcut": .text("Build")])
        ])
        workflow.policy.toolAllowlist = ["clipboard.read"]
        XCTAssertTrue(WorkflowValidator.validate(workflow).contains { $0.id.hasSuffix(".tools") })
    }

    func testCopilotAssemblerCreatesTypedDataAndControlConnections() {
        let workflow = WorkflowCopilotAssembler.assemble(name: "Open files", specs: [
            .init(kindIdentifier: "input.files", title: "Files", configuration: ""),
            .init(kindIdentifier: "action.open", title: "Open", configuration: "")
        ], policy: .init())
        XCTAssertTrue(WorkflowValidator.validate(workflow).filter { $0.severity == .error }.isEmpty)
        XCTAssertTrue(workflow.edges.contains { $0.sourcePortID == "objects" && $0.targetPortID == "objects" })
        XCTAssertTrue(workflow.edges.contains { $0.sourcePortID == "control" && $0.targetPortID == "control" })
    }
}

final class WorkflowModelRouterTests: XCTestCase {
    func testLocalOnlyNeverRoutesToProvider() {
        XCTAssertEqual(WorkflowModelRouter.decide(estimatedTokens: 10_000, modelPolicy: .automatic,
                                                  dataPolicy: .localOnly, providerApproved: false, providerAvailable: true), .onDevice)
        XCTAssertEqual(WorkflowModelRouter.decide(estimatedTokens: 100, modelPolicy: .externalProvider,
                                                  dataPolicy: .localOnly, providerApproved: true, providerAvailable: true), .forbiddenByLocalPolicy)
    }

    func testExplicitProviderRequiresApprovalWhenPolicyAsksEveryTime() {
        XCTAssertEqual(WorkflowModelRouter.decide(estimatedTokens: 100, modelPolicy: .externalProvider,
                                                  dataPolicy: .askEveryTime, providerApproved: false, providerAvailable: true), .approvalRequired)
        XCTAssertEqual(WorkflowModelRouter.decide(estimatedTokens: 100, modelPolicy: .externalProvider,
                                                  dataPolicy: .askEveryTime, providerApproved: true, providerAvailable: true), .externalProvider)
    }

    func testAutomaticUsesProviderOnlyForLargeEligiblePrompts() {
        XCTAssertEqual(WorkflowModelRouter.decide(estimatedTokens: 3_000, modelPolicy: .automatic,
                                                  dataPolicy: .externalProviderAllowed, providerApproved: false, providerAvailable: true), .onDevice)
        XCTAssertEqual(WorkflowModelRouter.decide(estimatedTokens: 3_500, modelPolicy: .automatic,
                                                  dataPolicy: .externalProviderAllowed, providerApproved: false, providerAvailable: true), .externalProvider)
    }
}

final class AIProviderConfigurationTests: XCTestCase {
    func testRemoteEndpointRequiresHTTPS() {
        var configuration = AIProviderConfiguration()
        configuration.endpoint = "http://example.com/v1/chat/completions"
        XCTAssertNotNil(configuration.validationMessage)
        configuration.endpoint = "http://localhost:11434/v1/chat/completions"
        XCTAssertNil(configuration.validationMessage)
        XCTAssertTrue(configuration.isLoopback)
    }

    func testProviderConfigurationDoesNotContainAPIKey() throws {
        let data = try JSONEncoder().encode(AIProviderConfiguration())
        XCTAssertFalse(String(decoding: data, as: UTF8.self).localizedCaseInsensitiveContains("apiKey"))
    }

    func testLegacyPCCPoliciesAndRouteMigrate() throws {
        XCTAssertEqual(try JSONDecoder().decode(WorkflowModelPolicy.self, from: Data("\"privateCloudCompute\"".utf8)), .externalProvider)
        XCTAssertEqual(try JSONDecoder().decode(WorkflowDataPolicy.self, from: Data("\"privateCloudAllowed\"".utf8)), .externalProviderAllowed)
        XCTAssertEqual(try JSONDecoder().decode(WorkflowModelRoute.self, from: Data("\"privateCloudCompute\"".utf8)), .externalProvider)
    }

    func testJSONDecoderAcceptsFencedProviderOutput() throws {
        struct Response: Decodable { let ok: Bool }
        XCTAssertTrue(try AIProviderClient.decodeJSON(Response.self, from: "```json\n{\"ok\":true}\n```").ok)
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
        let workflow = WorkflowDefinition(name: "Large", nodes: nodes)
        var bestValidation = TimeInterval.greatestFiniteMagnitude
        var bestLayout = TimeInterval.greatestFiniteMagnitude
        for _ in 0..<3 {
            var start = ContinuousClock.now
            _ = WorkflowValidator.validate(workflow)
            bestValidation = min(bestValidation, start.duration(to: .now).timeInterval)
            start = .now
            _ = WorkflowGraphEditor.automaticLayout(workflow)
            bestLayout = min(bestLayout, start.duration(to: .now).timeInterval)
        }
        XCTAssertLessThan(bestValidation, 0.100, "1,000-node validation exceeded the 100 ms budget")
        XCTAssertLessThan(bestLayout, 0.250, "1,000-node layout exceeded the 250 ms budget")
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
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

    final class VariableExecutor: WorkflowNodeExecuting {
        var receivedValue: WorkflowValue?
        func execute(node: WorkflowNode, inputs: [String: WorkflowValue], workflow: WorkflowDefinition) async throws -> WorkflowNodeExecutionResult {
            if node.title == "Producer" { return .init(outputs: ["value": .text("generated"), "control": .none], route: .deterministic, undoOperation: nil) }
            receivedValue = inputs["value"]
            return .init(outputs: ["control": .none], route: .deterministic, undoOperation: nil)
        }
    }

    func testDefaultsAndOutputVariablesResolveAtExecutionTime() async {
        let first = WorkflowNode(kindIdentifier: "input.clipboard", title: "Producer", outputVariable: "result")
        let second = WorkflowNode(kindIdentifier: "output.copy", title: "Consumer", configuration: ["value": .text("{{result}}")])
        let workflow = WorkflowDefinition(name: "Variables", nodes: [first, second], edges: [
            .init(sourceNodeID: first.id, sourcePortID: "control", targetNodeID: second.id, targetPortID: "control")
        ], variables: [.init(name: "unused", defaultValue: "default")])
        let executor = VariableExecutor()
        let engine = WorkflowExecutionEngine(executor: executor, receiptStore: WorkflowReceiptStore(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        let receipt = await engine.run(workflow)
        XCTAssertTrue(receipt.succeeded)
        XCTAssertEqual(executor.receivedValue, .text("generated"))
    }

    enum ExpectedFailure: Error { case failed }
    final class RollbackExecutor: WorkflowNodeExecuting {
        let createdURL: URL
        init(createdURL: URL) { self.createdURL = createdURL }
        func execute(node: WorkflowNode, inputs: [String: WorkflowValue], workflow: WorkflowDefinition) async throws -> WorkflowNodeExecutionResult {
            if node.title == "Create" {
                try Data("created".utf8).write(to: createdURL)
                let undo = FileUndoRecord(title: "Create", moves: [], createdURLs: [createdURL])
                return .init(outputs: ["control": .none], route: .deterministic, undoOperation: .init(undo))
            }
            throw ExpectedFailure.failed
        }
    }

    func testFailureRollsBackCompletedMutation() async {
        let URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = WorkflowNode(kindIdentifier: "logic.delay", title: "Create")
        let second = WorkflowNode(kindIdentifier: "logic.delay", title: "Fail")
        let workflow = WorkflowDefinition(name: "Rollback", nodes: [first, second], edges: [
            .init(sourceNodeID: first.id, sourcePortID: "control", targetNodeID: second.id, targetPortID: "control")
        ])
        let engine = WorkflowExecutionEngine(executor: RollbackExecutor(createdURL: URL), receiptStore: WorkflowReceiptStore(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        let receipt = await engine.run(workflow)
        XCTAssertFalse(receipt.succeeded)
        XCTAssertTrue(receipt.wasRolledBack)
        XCTAssertFalse(FileManager.default.fileExists(atPath: URL.path))
    }

    final class SlowExecutor: WorkflowNodeExecuting {
        func execute(node: WorkflowNode, inputs: [String: WorkflowValue], workflow: WorkflowDefinition) async throws -> WorkflowNodeExecutionResult {
            try await Task.sleep(for: .seconds(5))
            return .init(outputs: ["control": .none], route: .deterministic, undoOperation: nil)
        }
    }

    func testCancellationInterruptsActiveNode() async {
        let workflow = WorkflowDefinition(name: "Cancel", nodes: [WorkflowNode(kindIdentifier: "logic.delay")])
        let engine = WorkflowExecutionEngine(executor: SlowExecutor(), receiptStore: WorkflowReceiptStore(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        let task = Task { await engine.run(workflow) }
        try? await Task.sleep(for: .milliseconds(50))
        engine.cancel()
        let receipt = await task.value
        XCTAssertFalse(receipt.succeeded)
        XCTAssertEqual(engine.state, .cancelled)
    }

    func testDryRunListsMutationsAndToolsWithoutExecuting() {
        let executor = FakeExecutor()
        let engine = WorkflowExecutionEngine(executor: executor, receiptStore: WorkflowReceiptStore(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        let workflow = WorkflowDefinition(name: "Preview", nodes: [
            WorkflowNode(kindIdentifier: "output.copy", configuration: ["value": .text("hello")])
        ])
        let report = engine.dryRun(workflow)
        XCTAssertTrue(report.isReady)
        XCTAssertEqual(report.mutations, ["Copy Result"])
        XCTAssertEqual(report.requiredTools, ["clipboard.write"])
        XCTAssertTrue(executor.executed.isEmpty)
    }
}

final class WorkflowRunApprovalTests: XCTestCase {
    private func approvalWorkflow() -> WorkflowDefinition {
        let approval = WorkflowNode(kindIdentifier: "logic.approval", configuration: ["approved": .boolean(true)])
        let summarize = WorkflowNode(kindIdentifier: "ai.summarize",
                                     configuration: ["providerApproved": .boolean(true), "pccApproved": .boolean(true),
                                                     "prompt": .text("Summarize"), "input": .text("Notes")])
        var policy = WorkflowPolicy()
        policy.dataPolicy = .askEveryTime
        return WorkflowDefinition(name: "Approvals", nodes: [approval, summarize], policy: policy)
    }

    func testSavedRecipesNeverCarryRunApprovals() throws {
        let recipe = Recipe(workflow: approvalWorkflow())
        let nodes = try XCTUnwrap(recipe.workflow?.nodes)
        for key in WorkflowDefinition.runApprovalKeys {
            XCTAssertTrue(nodes.allSatisfy { $0.configuration[key] == nil }, key)
        }
        XCTAssertEqual(nodes.last?.configuration["prompt"], .text("Summarize"))
    }

    func testImportedRecipeJSONWithApprovalsIsStripped() throws {
        // Simulates a shared file that was crafted (or exported by an older build) with approvals set.
        let raw = try JSONEncoder().encode(approvalWorkflow())
        let json = #"{"id":"\#(UUID().uuidString)","name":"Shared","schemaVersion":2,"workflow":\#(String(decoding: raw, as: UTF8.self))}"#
        let recipe = try JSONDecoder().decode(Recipe.self, from: Data(json.utf8))
        let nodes = try XCTUnwrap(recipe.workflow?.nodes)
        XCTAssertTrue(nodes.allSatisfy { node in WorkflowDefinition.runApprovalKeys.allSatisfy { node.configuration[$0] == nil } })
    }

    @MainActor
    func testRecipeStoreImportStripsApprovals() throws {
        let suite = "RecipeApprovalImport.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let raw = try JSONEncoder().encode(approvalWorkflow())
        let json = #"[{"id":"\#(UUID().uuidString)","name":"Shared","schemaVersion":2,"workflow":\#(String(decoding: raw, as: UTF8.self))}]"#
        let store = RecipeStore(defaults: defaults)
        try store.importData(Data(json.utf8))
        let exported = String(decoding: try store.exportData(), as: UTF8.self)
        XCTAssertFalse(exported.contains("providerApproved"))
        XCTAssertFalse(exported.contains("\"approved\""))
    }

    func testApprovalCountsAndPerRunApproval() {
        let stripped = approvalWorkflow().strippingRunApprovals()
        XCTAssertEqual(stripped.approvalStepCount, 1)
        XCTAssertEqual(stripped.providerApprovalNodeCount, 1)
        let approved = stripped.approvedForThisRun()
        XCTAssertEqual(approved.nodes[0].configuration["approved"], .boolean(true))
        XCTAssertEqual(approved.nodes[1].configuration["providerApproved"], .boolean(true))

        var localOnly = stripped
        localOnly.policy.dataPolicy = .localOnly
        XCTAssertEqual(localOnly.providerApprovalNodeCount, 0)
    }
}

final class WorkflowAISafetyTests: XCTestCase {
    final class AIProducerExecutor: WorkflowNodeExecuting {
        let generated: String
        var executedTitles: [String] = []
        init(generated: String) { self.generated = generated }
        func execute(node: WorkflowNode, inputs: [String: WorkflowValue], workflow: WorkflowDefinition) async throws -> WorkflowNodeExecutionResult {
            executedTitles.append(node.title)
            if node.title == "Name" { return .init(outputs: ["result": .text(generated), "control": .none], route: .onDevice, undoOperation: nil) }
            return .init(outputs: ["value": inputs["value"] ?? .none, "control": .none], route: .deterministic, undoOperation: nil)
        }
    }

    private func workflow() -> WorkflowDefinition {
        let name = WorkflowNode(kindIdentifier: "input.clipboard", title: "Name", outputVariable: "name")
        let folder = WorkflowNode(kindIdentifier: "logic.delay", title: "Folder", configuration: ["seconds": .number(0), "value": .folder("/tmp/{{name}}")])
        return WorkflowDefinition(name: "AI path", nodes: [name, folder], edges: [
            .init(sourceNodeID: name.id, sourcePortID: "control", targetNodeID: folder.id, targetPortID: "control")
        ])
    }

    @MainActor
    func testAIOutputCannotTraverseOutOfAFilePath() async {
        let executor = AIProducerExecutor(generated: "../../Users/me/Documents")
        let engine = WorkflowExecutionEngine(executor: executor, receiptStore: WorkflowReceiptStore(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        let receipt = await engine.run(workflow())
        XCTAssertFalse(receipt.succeeded)
        XCTAssertEqual(executor.executedTitles, ["Name"])
        XCTAssertTrue(receipt.nodes.last?.error?.contains("plain file name") == true)
    }

    @MainActor
    func testPlainAIFileNameIsAllowedInAPath() async {
        let executor = AIProducerExecutor(generated: "Quarterly Report")
        let engine = WorkflowExecutionEngine(executor: executor, receiptStore: WorkflowReceiptStore(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        let receipt = await engine.run(workflow())
        XCTAssertTrue(receipt.succeeded)
        XCTAssertEqual(executor.executedTitles, ["Name", "Folder"])
    }

    func testGuardRules() {
        XCTAssertTrue(AIDerivedValueGuard.isSafePathComponent("Invoice 2026.pdf"))
        for unsafe in ["", ".", "..", "a/b", "~root", "line\nbreak", "C:evil"] {
            XCTAssertFalse(AIDerivedValueGuard.isSafePathComponent(unsafe), unsafe)
        }
        XCTAssertTrue(AIDerivedValueGuard.isSafeExistingPath(NSTemporaryDirectory()))
        XCTAssertFalse(AIDerivedValueGuard.isSafeExistingPath("/tmp/../etc"))
        XCTAssertFalse(AIDerivedValueGuard.isSafeExistingPath("relative/path"))
        XCTAssertEqual(AIDerivedValueGuard.encodedForURL("a b&c=d/e?#"), "a%20b%26c%3Dd%2Fe%3F%23")
    }
}

@MainActor
final class ObjectActionSafetyTests: XCTestCase {
    func testOpenRefusesNonWebSchemes() {
        XCTAssertThrowsError(try ObjectActionPerformer.openTarget("file:///tmp/run.command"))
        XCTAssertThrowsError(try ObjectActionPerformer.openTarget("x-launch://do-something"))
        XCTAssertEqual(try ObjectActionPerformer.openTarget("https://example.com").host, "example.com")
        XCTAssertTrue(try ObjectActionPerformer.openTarget(NSTemporaryDirectory()).isFileURL)
    }

    func testFileActionsFailWhenASourceIsMissing() async throws {
        let present = FileManager.default.temporaryDirectory.appendingPathComponent("present-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: present)
        defer { try? FileManager.default.removeItem(at: present) }
        let missing = "/tmp/missing-\(UUID().uuidString).txt"
        do {
            _ = try await ObjectActionPerformer().execute(kind: .duplicate, sources: [present.path, missing], target: nil)
            XCTFail("Expected a missing-source error")
        } catch let error as FileOperationError {
            XCTAssertEqual(error, .missingSource(missing))
        }
    }

    func testObjectStepSummaryNamesItems() {
        let step = RecipeStep.objectAction(.open, sources: ["/Users/me/a.pdf", "https://example.com", "/b.txt", "/c.txt"])
        XCTAssertEqual(step.summary, "Open a.pdf, https://example.com, b.txt and 1 more")
    }
}

final class WorkflowDuplicateIdentifierTests: XCTestCase {
    func testDuplicateNodeIdentifiersAreRejectedWithoutCrashing() {
        let id = UUID()
        let workflow = WorkflowDefinition(name: "Dup", nodes: [
            WorkflowNode(id: id, kindIdentifier: "logic.delay"), WorkflowNode(id: id, kindIdentifier: "logic.delay")
        ])
        XCTAssertTrue(WorkflowValidator.validate(workflow).contains { $0.id == "workflow.duplicate-nodes" })
        XCTAssertNotNil(WorkflowValidator.topologicalOrder(for: workflow) ?? [])
    }
}
