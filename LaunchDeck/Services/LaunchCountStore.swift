import Foundation
import LaunchDeckCore

/// Per-app launch counts for the "Most Launched" sort. Kept apart from the 12-entry recents
/// list, which would otherwise forget a frequently used app after 12 other launches. Apps not
/// launched for `retention` are dropped, and the privacy reset clears everything.
@MainActor
final class LaunchCountStore {
    struct Entry: Codable, Equatable {
        var count: Int
        var lastLaunch: Date
    }

    static let defaultRetention: TimeInterval = 180 * 24 * 3600
    private(set) var entries: [String: Entry]
    private let defaults: UserDefaults
    private let retention: TimeInterval
    private let key = "launcher.launchCounts.v1"

    init(defaults: UserDefaults = .standard, retention: TimeInterval = defaultRetention,
         seedingFrom recents: [RecentLaunch] = [], now: Date = .now) {
        self.defaults = defaults
        self.retention = retention
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            // First run with this store: keep the counts the recents list already had.
            entries = Dictionary(recents.map { ($0.identifier, Entry(count: $0.launchCount, lastLaunch: $0.lastLaunch)) },
                                 uniquingKeysWith: { first, _ in first })
        }
        purge(now: now)
    }

    var counts: [String: Int] { entries.mapValues(\.count) }

    func recordLaunch(of identifier: String, at date: Date = .now) {
        entries[identifier, default: Entry(count: 0, lastLaunch: date)].count += 1
        entries[identifier]?.lastLaunch = date
        purge(now: date)
    }

    func clear() {
        entries = [:]
        defaults.removeObject(forKey: key)
    }

    private func purge(now: Date) {
        entries = entries.filter { now.timeIntervalSince($0.value.lastLaunch) <= retention }
        defaults.set(try? JSONEncoder().encode(entries), forKey: key)
    }
}
