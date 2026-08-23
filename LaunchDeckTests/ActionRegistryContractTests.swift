import XCTest
@testable import LaunchDeck

@MainActor
final class ActionRegistryContractTests: XCTestCase {
    func testEveryRegisteredActionResolvesWithTypedParameters() {
        let recipe = Recipe(name: "Work", steps: [.openTerminal(directory: "/tmp")])
        let cases: [(String, [String: String], LaunchDeckAction)] = [
            ("open.application", ["identifier": "com.test.app", "name": "Test"], .openApplication(identifier: "com.test.app", name: "Test")),
            ("open.file", ["path": "/tmp/a"], .openFile(path: "/tmp/a", applicationIdentifier: nil, applicationName: nil)),
            ("open.file-with", ["path": "/tmp/a", "applicationIdentifier": "com.test.app", "applicationName": "Test"], .openFile(path: "/tmp/a", applicationIdentifier: "com.test.app", applicationName: "Test")),
            ("reveal.finder", ["identifier": "com.test.app", "name": "Test"], .revealApplication(identifier: "com.test.app", name: "Test")),
            ("open.project", ["path": "/tmp/project"], .openProject(path: "/tmp/project")),
            ("run.shortcut", ["name": "Export"], .runShortcut(name: "Export")),
            ("open.terminal", ["directory": "/tmp"], .openTerminal(directory: "/tmp")),
            ("run.recipe", ["identifier": recipe.id.uuidString], .runRecipe(identifier: recipe.id, name: recipe.name, steps: recipe.steps)),
            ("open.settings", ["identifier": SystemSettingsDestination.keyboard.rawValue], .openSystemSettings(destination: .keyboard)),
        ]
        XCTAssertEqual(Set(cases.map(\.0)), ActionRegistry.shared.identifiers)
        for (identifier, parameters, expected) in cases {
            XCTAssertEqual(ActionRegistry.shared.resolve(actionIdentifier: identifier, parameters: parameters, recipes: [recipe]), expected)
        }
    }

    func testDescriptorConfirmationContractMatchesResolvedActions() {
        XCTAssertEqual(ActionRegistry.shared.descriptors.first { $0.id == "run.shortcut" }?.requiresConfirmation, true)
        XCTAssertEqual(ActionRegistry.shared.descriptors.first { $0.id == "open.application" }?.requiresConfirmation, false)
    }
}
