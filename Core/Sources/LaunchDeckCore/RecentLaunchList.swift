import Foundation

/// Maintains the recently-launched list: most recent first, capped at `maxCount`.
public enum RecentLaunchList {
    public static func recordingLaunch(of app: DiscoveredApp,
                                       in recents: [RecentLaunch],
                                       maxCount: Int,
                                       at date: Date = Date()) -> [RecentLaunch] {
        var updated = recents

        if let index = updated.firstIndex(where: { $0.identifier == app.identifier }) {
            var launch = updated.remove(at: index)
            launch.lastLaunch = date
            launch.launchCount += 1
            updated.insert(launch, at: 0)
        } else {
            let launch = RecentLaunch(identifier: app.identifier,
                                      displayName: app.name,
                                      path: app.path,
                                      lastLaunch: date,
                                      launchCount: 1)
            updated.insert(launch, at: 0)
        }

        if updated.count > maxCount {
            updated = Array(updated.prefix(maxCount))
        }

        return updated
    }
}
