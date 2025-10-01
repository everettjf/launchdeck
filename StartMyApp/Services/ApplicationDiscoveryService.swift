import Foundation

final class ApplicationDiscoveryService {
    private let fileManager: FileManager
    private let searchPaths: [URL]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        var paths: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true)
        ]

        if let userApplications = try? fileManager.url(for: .applicationDirectory,
                                                       in: .userDomainMask,
                                                       appropriateFor: nil,
                                                       create: false) {
            paths.append(userApplications)
        } else {
            let homeApplications = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
            paths.append(homeApplications)
        }

        self.searchPaths = paths
    }

    func discoverApplications(includeSystemApps: Bool) -> [DiscoveredApp] {
        var applications: [String: DiscoveredApp] = [:]

        for baseURL in searchPaths {
            guard let enumerator = fileManager.enumerator(at: baseURL,
                                                          includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                                                          options: [.skipsHiddenFiles]) else {
                continue
            }

            for case let url as URL in enumerator {
                if url.lastPathComponent.hasSuffix(".app") == false {
                    continue
                }

                enumerator.skipDescendants()

                guard let app = makeApp(from: url) else { continue }
                if !includeSystemApps && app.isSystemApp {
                    continue
                }
                if applications[app.identifier] != nil {
                    continue
                }
                applications[app.identifier] = app
            }
        }

        return Array(applications.values)
    }

    private func makeApp(from url: URL) -> DiscoveredApp? {
        guard let bundle = Bundle(url: url) else { return nil }

        let bundleIdentifier = bundle.bundleIdentifier
        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let category = categoryDisplayName(from: bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String)
        let keywords = extractKeywords(for: bundle)
        let developer = developerName(from: bundleIdentifier)
        let isSystem = isSystemApplication(bundleIdentifier: bundleIdentifier, url: url)

        return DiscoveredApp(name: displayName,
                             bundleIdentifier: bundleIdentifier,
                             path: url.path,
                             category: category,
                             bundleVersion: version,
                             developer: developer,
                             isSystemApp: isSystem,
                             keywords: keywords)
    }

    private func categoryDisplayName(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        guard let lastComponent = rawValue.split(separator: ".").last else { return nil }
        let transformed = lastComponent
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
        return transformed
    }

    private func developerName(from bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier else { return nil }
        let parts = bundleIdentifier.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let candidate = parts[1]
        return candidate.prefix(1).uppercased() + candidate.dropFirst()
    }

    private func isSystemApplication(bundleIdentifier: String?, url: URL) -> Bool {
        if url.path.hasPrefix("/System/Applications") { return true }
        if url.path.hasPrefix("/Applications/Utilities") { return true }
        if let bundleIdentifier, bundleIdentifier.hasPrefix("com.apple") {
            return true
        }
        return false
    }

    private func extractKeywords(for bundle: Bundle) -> [String] {
        var keywords: Set<String> = []
        if let bundleIdentifier = bundle.bundleIdentifier {
            keywords.insert(bundleIdentifier)
            bundleIdentifier.split(separator: ".").forEach { keywords.insert(String($0)) }
        }
        if let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            keywords.insert(shortVersion)
        }
        if let version = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            keywords.insert(version)
        }
        if let executableName = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String {
            keywords.insert(executableName)
        }
        if let category = bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String {
            category.split(separator: ".").forEach { keywords.insert(String($0)) }
        }
        return Array(keywords)
    }
}
