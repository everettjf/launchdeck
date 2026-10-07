import Foundation

/// Non-custom sort orders for the app grid. Each returns app identifiers.
public enum AppSorting {
    public static func alphabetical(_ apps: [DiscoveredApp]) -> [String] {
        apps
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { $0.identifier }
    }

    public static func mostLaunched(_ apps: [DiscoveredApp], recents: [RecentLaunch]) -> [String] {
        mostLaunched(apps, launchCounts: Dictionary(recents.map { ($0.identifier, $0.launchCount) },
                                                    uniquingKeysWith: { first, _ in first }))
    }

    public static func mostLaunched(_ apps: [DiscoveredApp], launchCounts: [String: Int]) -> [String] {
        apps
            .sorted { first, second in
                let firstCount = launchCounts[first.identifier] ?? 0
                let secondCount = launchCounts[second.identifier] ?? 0
                if firstCount == secondCount {
                    return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                }
                return firstCount > secondCount
            }
            .map { $0.identifier }
    }

    public static func recentlyLaunched(_ apps: [DiscoveredApp], recents: [RecentLaunch]) -> [String] {
        let recentsLookup = Dictionary(recents.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        return apps
            .sorted { first, second in
                let firstDate = recentsLookup[first.identifier]?.lastLaunch
                let secondDate = recentsLookup[second.identifier]?.lastLaunch
                switch (firstDate, secondDate) {
                case let (lhs?, rhs?):
                    if lhs == rhs {
                        return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                    }
                    return lhs > rhs
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                }
            }
            .map { $0.identifier }
    }
}
