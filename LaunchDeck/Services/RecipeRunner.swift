import AppKit
import Combine
import Foundation

nonisolated struct RecipeStepLog: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let stepID: UUID
    let summary: String
    let startedAt: Date
    let duration: TimeInterval
    let attempts: Int
    let outcome: String
}

nonisolated struct RecipeExecutionLog: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let recipeName: String
    let startedAt: Date
    let succeeded: Bool
    let steps: [RecipeStepLog]
}

@MainActor
final class RecipeExecutionLogStore: ObservableObject {
    @Published private(set) var entries: [RecipeExecutionLog]
    private let defaults: UserDefaults
    private let key = "recipe.executionLogs.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([RecipeExecutionLog].self, from: $0) } ?? []
    }

    func append(_ entry: RecipeExecutionLog) {
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(50))
        defaults.set(try? JSONEncoder().encode(entries), forKey: key)
    }

    func clear() {
        entries = []
        defaults.removeObject(forKey: key)
    }
}

nonisolated struct RecipeRunReport: Sendable {
    let succeeded: Bool
    let stepLogs: [RecipeStepLog]
}

enum RecipeRunner {
    static func run(_ steps: [RecipeStep], execute: (RecipeStep) async -> Bool) async -> Bool {
        await runDetailed(steps, execute: execute).succeeded
    }

    static func runDetailed(_ steps: [RecipeStep], execute: (RecipeStep) async -> Bool) async -> RecipeRunReport {
        var allSucceeded = true
        var outputs: [String: String] = [:]
        var logs: [RecipeStepLog] = []

        for originalStep in steps {
            let step = RecipeVariableResolver.substitute(originalStep, replacements: outputs)
            let startedAt = Date()
            if !conditionMatches(step.condition) {
                logs.append(.init(id: UUID(), stepID: step.id, summary: step.summary, startedAt: startedAt,
                                  duration: 0, attempts: 0, outcome: "skipped"))
                continue
            }

            var succeeded = false
            var attempts = 0
            repeat {
                attempts += 1
                succeeded = await execute(step)
            } while !succeeded && attempts <= step.retryCount

            let effectiveSuccess = succeeded || step.isOptional
            allSucceeded = allSucceeded && effectiveSuccess
            if succeeded, let outputVariable = step.outputVariable, !outputVariable.isEmpty {
                outputs[outputVariable] = outputValue(for: step.operation)
            }
            logs.append(.init(id: UUID(), stepID: step.id, summary: step.summary, startedAt: startedAt,
                              duration: Date().timeIntervalSince(startedAt), attempts: attempts,
                              outcome: succeeded ? "succeeded" : (step.isOptional ? "optional-failure" : "failed")))
            if !effectiveSuccess, step.failurePolicy == .stop {
                return RecipeRunReport(succeeded: false, stepLogs: logs)
            }
        }
        return RecipeRunReport(succeeded: allSucceeded, stepLogs: logs)
    }

    static func conditionMatches(_ condition: RecipeStep.Condition?) -> Bool {
        switch condition {
        case .fileExists(let path): return FileManager.default.fileExists(atPath: path)
        case .applicationRunning(let identifier):
            return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == identifier }
        case .valueEquals(let lhs, let rhs): return lhs == rhs
        case nil: return true
        }
    }

    private static func outputValue(for operation: RecipeStep.Operation) -> String {
        switch operation {
        case .openApplication(let identifier, _): identifier
        case .openProject(let path), .openTerminal(let path), .runShortcut(let path): path
        case .delay(let seconds): seconds.formatted()
        case .objectAction(_, let sources, let target): target ?? sources.first ?? ""
        }
    }
}
