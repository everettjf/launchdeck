import Foundation

final class FavoritesStore {
    private let defaults: UserDefaults
    private let key = "launcher.favorites"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    func save(_ favorites: Set<String>) {
        defaults.set(Array(favorites), forKey: key)
    }
}
