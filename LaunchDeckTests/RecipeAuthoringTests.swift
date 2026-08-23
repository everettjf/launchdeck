import Foundation
import Testing
@testable import LaunchDeck

struct RecipeAuthoringTests {
    @Test func resolvesVariablesAcrossTypedStepsAndPreservesStepIdentity() {
        let steps: [RecipeStep] = [.openProject(path: "{{projectPath}}"), .openTerminal(directory: "{{projectPath}}")]
        let result = RecipeVariableResolver.resolve(
            steps: steps,
            variables: [RecipeVariable(name: "projectPath")],
            values: ["projectPath": "/tmp/demo"]
        )
        guard case .resolved(let resolved) = result else { Issue.record("Expected resolved steps"); return }
        #expect(resolved.map(\.id) == steps.map(\.id))
        #expect(resolved[0].operation == .openProject(path: "/tmp/demo"))
        #expect(resolved[1].operation == .openTerminal(directory: "/tmp/demo"))
    }

    @Test func reportsEveryMissingVariableInStableOrder() {
        let steps: [RecipeStep] = [.openProject(path: "{{workspace}}/{{project}}")]
        let result = RecipeVariableResolver.resolve(
            steps: steps,
            variables: [RecipeVariable(name: "workspace"), RecipeVariable(name: "project")],
            values: [:]
        )
        #expect(result == .missing(["project", "workspace"]))
    }

    @Test func defaultsCanSatisfyVariablesAndUserValuesOverrideThem() {
        let steps: [RecipeStep] = [.runShortcut(name: "{{shortcut}}")]
        let variable = RecipeVariable(name: "shortcut", defaultValue: "Default")
        #expect(RecipeVariableResolver.resolve(steps: steps, variables: [variable], values: [:]) ==
                .resolved([RecipeStep(id: steps[0].id, operation: .runShortcut(name: "Default"))]))
        #expect(RecipeVariableResolver.resolve(steps: steps, variables: [variable], values: ["shortcut": "Override"]) ==
                .resolved([RecipeStep(id: steps[0].id, operation: .runShortcut(name: "Override"))]))
    }

    @Test func substitutionSupportsArbitraryPlaceholderWhitespace() {
        let step = RecipeStep.openProject(path: "/tmp/{{   project_name   }}")
        let result = RecipeVariableResolver.resolve(
            steps: [step], variables: [RecipeVariable(name: "project_name")], values: ["project_name": "Demo"]
        )
        #expect(result == .resolved([RecipeStep(id: step.id, operation: .openProject(path: "/tmp/Demo"))]))
    }

    @Test func recipesDecodeOlderPayloadsWithoutVariables() throws {
        struct LegacyRecipe: Encodable { let id: UUID; let name: String; let steps: [RecipeStep] }
        let id = UUID()
        let step = RecipeStep.openTerminal(directory: "/tmp")
        let payload = try JSONEncoder().encode(LegacyRecipe(id: id, name: "Legacy", steps: [step]))
        let recipe = try JSONDecoder().decode(Recipe.self, from: payload)
        #expect(recipe.variables.isEmpty)
        #expect(recipe.steps == [step])
    }

    @Test func validationRejectsUndeclaredAndDuplicateVariables() {
        let undeclared = Recipe(name: "Bad", steps: [.openProject(path: "{{root}}")])
        #expect(RecipeValidation.error(for: undeclared)?.contains("root") == true)
        let duplicate = Recipe(name: "Bad", variables: [RecipeVariable(name: "root"), RecipeVariable(name: "root")],
                               steps: [.openProject(path: "{{root}}")])
        #expect(RecipeValidation.error(for: duplicate)?.contains("unique") == true)
    }

    @Test func reorderMovesStableIdentitiesAndRejectsInvalidIndices() {
        let steps: [RecipeStep] = [.openProject(path: "a"), .openProject(path: "b"), .openProject(path: "c")]
        #expect(RecipeStepOrder.moving(steps, from: 0, to: 3).map(\.id) == [steps[1].id, steps[2].id, steps[0].id])
        #expect(RecipeStepOrder.moving(steps, from: -1, to: 2) == steps)
    }

    @Test func allBuiltInTemplatesHaveUniqueIDsAndValidResolvableSteps() {
        let templates = RecipeTemplateCatalog.templates
        #expect(Set(templates.map(\.id)).count == templates.count)
        for template in templates {
            let values = Dictionary(uniqueKeysWithValues: template.variables.map {
                ($0.name, $0.valueType == .file || $0.valueType == .folder ? "/tmp" : "value")
            })
            guard case .resolved(let steps) = RecipeVariableResolver.resolve(
                steps: template.steps, variables: template.variables, values: values
            ) else { Issue.record("Template did not resolve: \(template.id)"); continue }
            #expect(RecipeValidation.error(for: Recipe(name: template.name, steps: steps)) == nil)
        }
    }

    @Test func outputVariablesRemainDeferredUntilExecution() {
        let first = RecipeStep(operation: .openProject(path: "{{root}}"), outputVariable: "opened")
        let second = RecipeStep(operation: .openTerminal(directory: "{{opened}}"))
        let result = RecipeVariableResolver.resolve(steps: [first, second],
                                                    variables: [RecipeVariable(name: "root")],
                                                    values: ["root": "/tmp"])
        guard case .resolved(let steps) = result else { Issue.record("Expected resolution"); return }
        #expect(steps[0].operation == .openProject(path: "/tmp"))
        #expect(steps[1].operation == .openTerminal(directory: "{{opened}}"))
        #expect(RecipeValidation.error(for: Recipe(name: "Outputs", variables: [RecipeVariable(name: "root")], steps: steps)) == nil)
    }

    @Test func typedVariablesRejectInvalidChoices() {
        let variable = RecipeVariable(name: "mode", valueType: .choice, choices: ["debug", "release"])
        let steps = [RecipeStep.openTerminal(directory: "{{mode}}")]
        guard case .invalid(let errors) = RecipeVariableResolver.resolve(
            steps: steps, variables: [variable], values: ["mode": "unsafe"]
        ) else { Issue.record("Expected invalid typed variable"); return }
        #expect(errors.count == 1)
    }

    @Test func dryRunReportsPermissionsWithoutExecution() {
        let recipe = Recipe(name: "Safe", steps: [.runShortcut(name: "Export")])
        let report = RecipeDryRun.inspect(recipe, values: [:], approvedShortcuts: ["Export"])
        #expect(report.isReady)
        #expect(report.permissions == ["Runs an approved Apple Shortcut"])
    }
}
