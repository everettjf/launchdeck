import XCTest
@testable import LaunchDeck

@MainActor
final class ActionSafetyTests: XCTestCase {
    func testShortcutRequiresApprovalAndConfirmation() {
        let controller = ActionController()
        controller.request(.runShortcut(name: "Export PDF"), approvedShortcuts: [])
        XCTAssertNil(controller.pendingAction)
        XCTAssertNotNil(controller.lastError)

        controller.request(.runShortcut(name: "Export PDF"), approvedShortcuts: ["Export PDF"])
        XCTAssertEqual(controller.pendingAction, .runShortcut(name: "Export PDF"))
        XCTAssertEqual(controller.pendingPreview?.risk, .elevated)
        controller.cancelPending()
        XCTAssertNil(controller.pendingAction)
    }

    func testEveryElevatedActionProducesPreviewBeforeExecution() {
        let actions: [(LaunchDeckAction, Set<String>)] = [
            (.openURL(URL(string: "https://example.com")!), []),
            (.runShortcut(name: "Export"), ["Export"]),
            (.openTerminal(directory: "/tmp"), []),
            (.runRecipe(identifier: UUID(), name: "Terminal", steps: [.openTerminal(directory: "/tmp")]), []),
        ]
        for (action, approvals) in actions {
            let controller = ActionController()
            controller.request(action, approvedShortcuts: approvals)
            XCTAssertEqual(controller.pendingPreview?.action, action)
            XCTAssertNil(controller.lastError)
            controller.cancelPending()
        }
    }

    func testRegistryRequiresTypedParameters() {
        let registry = ActionRegistry.shared
        XCTAssertEqual(registry.missingParameters(actionIdentifier: "open.project", parameters: [:]), ["path"])
        XCTAssertEqual(registry.resolve(actionIdentifier: "open.project", parameters: ["path": "/tmp/Demo.xcodeproj"]),
                       .openProject(path: "/tmp/Demo.xcodeproj"))
        XCTAssertNil(registry.resolve(actionIdentifier: "unknown", parameters: [:]))
    }

    func testRecipeRoundTripAndPreviewListsAllSteps() throws {
        let suite = "RecipeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RecipeStore(defaults: defaults)
        let recipe = Recipe(name: "Start Work", steps: [.openProject(path: "/tmp/Deck.xcodeproj"), .openTerminal(directory: "/tmp")])
        try store.save(recipe)
        let data = try store.exportData()
        let imported = RecipeStore(defaults: UserDefaults(suiteName: "\(suite)-import")!)
        try imported.importData(data)
        XCTAssertEqual(imported.recipes, [recipe])
        let preview = ActionPreview(action: .runRecipe(identifier: recipe.id, name: recipe.name, steps: recipe.steps))
        XCTAssertEqual(preview.steps.count, 2)
        XCTAssertEqual(preview.risk, .elevated)
        XCTAssertEqual(Set(preview.steps.map(\.id)).count, 2)
        XCTAssertTrue(preview.permissions.contains { $0.contains("Terminal") })
    }

    func testRecipeCannotBypassShortcutApproval() {
        let recipe = LaunchDeckAction.runRecipe(identifier: UUID(), name: "Unsafe", steps: [.runShortcut(name: "Delete Files")])
        XCTAssertNotNil(ActionPolicy.validate(recipe, approvedShortcuts: []))
        XCTAssertNil(ActionPolicy.validate(recipe, approvedShortcuts: ["Delete Files"]))
    }

    func testActionsRejectMissingOrWrongPathTypes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LaunchDeckPolicy-\(UUID().uuidString)")
        let file = root.appendingPathComponent("note.md")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data()))
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertNil(ActionPolicy.validate(.openFile(path: file.path, applicationIdentifier: nil, applicationName: nil), approvedShortcuts: []))
        XCTAssertNotNil(ActionPolicy.validate(.openFile(path: root.path, applicationIdentifier: nil, applicationName: nil), approvedShortcuts: []))
        XCTAssertNil(ActionPolicy.validate(.openTerminal(directory: root.path), approvedShortcuts: []))
        XCTAssertNotNil(ActionPolicy.validate(.openTerminal(directory: file.path), approvedShortcuts: []))
    }

    func testRecipeValidationRejectsDuplicateStepIdentityAndInvalidImport() throws {
        let id = UUID()
        let duplicated = RecipeStep(id: id, operation: .openTerminal(directory: "/tmp"))
        let recipe = Recipe(name: "Duplicate", steps: [duplicated, duplicated])
        XCTAssertNotNil(RecipeValidation.error(for: recipe))

        let suite = "InvalidRecipeImport-\(UUID().uuidString)"
        let store = RecipeStore(defaults: UserDefaults(suiteName: suite)!)
        let data = try JSONEncoder().encode([Recipe(name: "", steps: [])])
        XCTAssertThrowsError(try store.importData(data))
    }

    func testURLPolicyRejectsNonWebSchemes() {
        let action = LaunchDeckAction.openURL(URL(string: "file:///tmp/private")!)
        XCTAssertNotNil(ActionPolicy.validate(action, approvedShortcuts: []))
        let web = LaunchDeckAction.openURL(URL(string: "https://example.com")!)
        XCTAssertNil(ActionPolicy.validate(web, approvedShortcuts: []))
    }

    func testHistoryCanBeCleared() {
        let suite = "ActionSafetyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ActionHistoryStore(defaults: defaults)
        let action = LaunchDeckAction.openSystemSettings(destination: .keyboard)
        store.record(action: action, succeeded: true)
        XCTAssertEqual(store.load().count, 1)
        store.clear()
        XCTAssertTrue(store.load().isEmpty)
    }
}
