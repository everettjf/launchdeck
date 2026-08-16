import Foundation
import LaunchDeckCore

final class RecentsStore {
    let maxCount: Int
    private let defaults: UserDefaults
    private let key = "launcher.recents"

    init(maxCount: Int, defaults: UserDefaults = .standard) {
        self.maxCount = maxCount
        self.defaults = defaults
    }

    func load() -> [RecentLaunch] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            let decoded = try JSONDecoder().decode([RecentLaunch].self, from: data)
            return decoded
        } catch {
            NSLog("Failed to decode recent launches: \(error)")
            return []
        }
    }

    func save(_ launches: [RecentLaunch]) {
        do {
            let data = try JSONEncoder().encode(launches)
            defaults.set(data, forKey: key)
        } catch {
            NSLog("Failed to encode recent launches: \(error)")
        }
    }
}
