import Foundation

public struct RecentLaunch: Codable, Identifiable, Hashable, Sendable {
    public let identifier: String
    public var displayName: String
    public var path: String
    public var lastLaunch: Date
    public var launchCount: Int

    public init(identifier: String, displayName: String, path: String, lastLaunch: Date, launchCount: Int) {
        self.identifier = identifier
        self.displayName = displayName
        self.path = path
        self.lastLaunch = lastLaunch
        self.launchCount = launchCount
    }

    public var id: String { identifier }
}
