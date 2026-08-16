import Foundation

public struct DiscoveredApp: Identifiable, Hashable, Sendable {
    public let name: String
    public let bundleIdentifier: String?
    public let path: String
    public let category: String?
    public let bundleVersion: String?
    public let developer: String?
    public let isSystemApp: Bool
    public let keywords: [String]

    public init(name: String,
                bundleIdentifier: String?,
                path: String,
                category: String?,
                bundleVersion: String?,
                developer: String?,
                isSystemApp: Bool,
                keywords: [String]) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.path = path
        self.category = category
        self.bundleVersion = bundleVersion
        self.developer = developer
        self.isSystemApp = isSystemApp
        self.keywords = keywords
    }

    public var id: String { bundleIdentifier ?? path }
    public var identifier: String { id }

    public var searchableText: String {
        (
            [name, bundleIdentifier, developer, category, bundleVersion]
                .compactMap { $0?.lowercased() } + keywords.map { $0.lowercased() }
        )
        .joined(separator: " ")
    }

    public var subtitle: String {
        if let developer, let category {
            return "\(developer) • \(category)"
        }
        if let developer {
            return developer
        }
        if let category {
            return category
        }
        return path
    }
}
