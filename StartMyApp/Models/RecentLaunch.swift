import Foundation

struct RecentLaunch: Codable, Identifiable, Hashable {
    let identifier: String
    var displayName: String
    var path: String
    var lastLaunch: Date
    var launchCount: Int

    var id: String { identifier }
}
