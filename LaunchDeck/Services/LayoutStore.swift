import Foundation
import LaunchDeckCore

final class LayoutStore {
    private let defaults: UserDefaults
    private let key = "launcher.layout"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [AppCollectionItem] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([AppCollectionItem].self, from: data)
        } catch {
            NSLog("Failed to decode layout: \(error)")
            return []
        }
    }

    func save(_ layout: [AppCollectionItem]) {
        do {
            let data = try JSONEncoder().encode(layout)
            defaults.set(data, forKey: key)
        } catch {
            NSLog("Failed to encode layout: \(error)")
        }
    }
}
