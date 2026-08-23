import Combine
import Foundation

@MainActor
final class RecipeStore: ObservableObject {
    @Published private(set) var recipes: [Recipe]
    private let defaults: UserDefaults
    private let key = "recipes.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recipes = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Recipe].self, from: $0) } ?? []
    }

    func save(_ recipe: Recipe) throws {
        if let message = RecipeValidation.error(for: recipe) { throw RecipeStoreError.invalidRecipe(message) }
        if let index = recipes.firstIndex(where: { $0.id == recipe.id }) { recipes[index] = recipe }
        else { recipes.append(recipe) }
        persist()
    }

    func remove(id: UUID) { recipes.removeAll { $0.id == id }; persist() }
    func exportData() throws -> Data { try JSONEncoder().encode(recipes) }
    func importData(_ data: Data) throws {
        let imported = try JSONDecoder().decode([Recipe].self, from: data)
        if let message = imported.compactMap(RecipeValidation.error).first {
            throw RecipeStoreError.invalidRecipe(message)
        }
        var merged = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        imported.forEach { merged[$0.id] = $0 }
        recipes = merged.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist()
    }
    private func persist() { defaults.set(try? JSONEncoder().encode(recipes), forKey: key) }
}

enum RecipeStoreError: LocalizedError {
    case invalidRecipe(String)
    var errorDescription: String? {
        switch self { case .invalidRecipe(let message): message }
    }
}
