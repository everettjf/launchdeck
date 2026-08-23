import Foundation

enum RecipeTrigger {
    static func recipeID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == "launchdeck", url.host?.lowercased() == "recipe" else { return nil }
        let value = url.pathComponents.filter { $0 != "/" }.first
        return value.flatMap(UUID.init(uuidString:))
    }
}
