import Foundation

final class ActionHistoryStore {
    private let defaults: UserDefaults
    private let key = "actions.history"
    private let limit: Int

    init(defaults: UserDefaults = .standard, limit: Int = 50) {
        self.defaults = defaults
        self.limit = limit
    }

    func load() -> [ActionHistoryEntry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ActionHistoryEntry].self, from: data)) ?? []
    }

    func record(action: LaunchDeckAction, succeeded: Bool) {
        var history = load()
        history.insert(ActionHistoryEntry(id: UUID(), actionID: action.historyID, title: action.historyTitle,
                                          date: Date(), succeeded: succeeded), at: 0)
        if history.count > limit { history.removeLast(history.count - limit) }
        if let data = try? JSONEncoder().encode(history) { defaults.set(data, forKey: key) }
    }

    func clear() { defaults.removeObject(forKey: key) }
}
