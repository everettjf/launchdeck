import AppKit
import Foundation

/// Runs saved recipes from every entry point (search, intents, deep links, Settings).
/// Workflow recipes go through the workflow engine; legacy step recipes go through
/// ActionController's confirmation and policy checks.
@MainActor
final class RecipeRunCoordinator {
    private let workflowExecutionEngine: WorkflowExecutionEngine
    private let actionController: ActionController
    private let approvedShortcuts: () -> Set<String>

    init(workflowExecutionEngine: WorkflowExecutionEngine, actionController: ActionController,
         approvedShortcuts: @escaping () -> Set<String>) {
        self.workflowExecutionEngine = workflowExecutionEngine
        self.actionController = actionController
        self.approvedShortcuts = approvedShortcuts
    }

    /// Runs a saved recipe. Missing variable values are asked for; workflow recipes go through
    /// the workflow engine with a dry run, mutation confirmation and per-run approvals.
    func run(_ recipe: Recipe, values providedValues: [String: String]? = nil) {
        var values = providedValues ?? [:]
        if providedValues == nil {
            for variable in recipe.resolvedWorkflow.variables {
                guard let value = UserPrompt.text(title: "Run \(recipe.name)",
                                         message: "Value for \(variable.name) (\(variable.valueType.rawValue)):",
                                         value: variable.defaultValue) else { return }
                values[variable.name] = value
            }
        }
        guard recipe.workflow != nil else {
            switch RecipeVariableResolver.resolve(steps: recipe.steps, variables: recipe.variables, values: values) {
            case .resolved(let steps):
                actionController.request(.runRecipe(identifier: recipe.id, name: recipe.name, steps: steps),
                                         approvedShortcuts: approvedShortcuts())
            case .missing(let names):
                actionController.presentError("Enter values for: \(names.joined(separator: ", ")).")
            case .invalid(let errors):
                actionController.presentError(errors.joined(separator: "\n"))
            }
            return
        }
        var workflow = recipe.resolvedWorkflow
        let preview = workflowExecutionEngine.dryRun(workflow)
        guard preview.isReady else {
            actionController.presentError(preview.issues.first(where: { $0.severity == .error })?.message ?? "The workflow is invalid.")
            return
        }
        if workflow.policy.requiresDryRunBeforeMutation, preview.requiresConfirmation {
            let alert = NSAlert()
            alert.messageText = "Run “\(workflow.name)”?"
            alert.informativeText = "Mutations: \(preview.mutations.joined(separator: ", "))\nTools: \(preview.requiredTools.sorted().joined(separator: ", "))"
            alert.addButton(withTitle: "Run")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let approvalSteps = workflow.approvalStepCount
        let providerBlocks = workflow.providerApprovalNodeCount
        if approvalSteps > 0 || providerBlocks > 0 {
            var reasons: [String] = []
            if approvalSteps > 0 { reasons.append("\(approvalSteps) approval step\(approvalSteps == 1 ? "" : "s")") }
            if providerBlocks > 0 {
                reasons.append("\(providerBlocks) AI block\(providerBlocks == 1 ? "" : "s") that may send input to your external AI provider")
            }
            let alert = NSAlert()
            alert.messageText = "Approve “\(workflow.name)” for this run?"
            alert.informativeText = "This workflow includes \(reasons.joined(separator: " and ")). Approval applies to this run only."
            alert.addButton(withTitle: "Approve and Run")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            workflow = workflow.approvedForThisRun()
        }
        Task { [workflowExecutionEngine, actionController, workflow, values] in
            let receipt = await workflowExecutionEngine.run(workflow, variableValues: values)
            if !receipt.succeeded {
                actionController.presentError(receipt.nodes.last?.error ?? "The workflow could not run.")
            }
        }
    }
}
