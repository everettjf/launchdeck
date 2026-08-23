enum RecipeRunner {
    static func run(_ steps: [RecipeStep], execute: (RecipeStep) async -> Bool) async -> Bool {
        var allSucceeded = true
        for step in steps {
            let succeeded = await execute(step)
            allSucceeded = allSucceeded && succeeded
            if !succeeded, step.failurePolicy == .stop { return false }
        }
        return allSucceeded
    }
}
