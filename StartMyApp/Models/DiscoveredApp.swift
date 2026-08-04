import Foundation

public struct DiscoveredApp: Identifiable, Hashable {
    let name: String
    let bundleIdentifier: String?
    let path: String
    let category: String?
    let bundleVersion: String?
    let developer: String?
    let isSystemApp: Bool
    let keywords: [String]

    public var id: String { bundleIdentifier ?? path }
    public var identifier: String { id }

    var searchableText: String {
        (
            [name, bundleIdentifier, developer, category, bundleVersion]
                .compactMap { $0?.lowercased() } + keywords.map { $0.lowercased() }
        )
        .joined(separator: " ")
    }

    var subtitle: String {
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
