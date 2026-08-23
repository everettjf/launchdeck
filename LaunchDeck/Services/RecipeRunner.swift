enum RecipeRunner {
    static func run(_ steps: [RecipeStep], execute: (RecipeStep) async -> Bool) async -> Bool {
        for step in steps {
            guard await execute(step) else { return false }
        }
        return true
    }
}
