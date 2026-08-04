import Foundation

public final class ApplicationDiscoveryService {
    private let fileManager: FileManager
    private let searchPaths: [URL]
    private let lock = NSLock()
    private var cachedAppsByPath: [String: CachedApp] = [:]

    private struct CachedApp {
        let modificationDate: Date?
        let app: DiscoveredApp
    }

    public init(fileManager: FileManager = .default, searchPaths: [URL]? = nil) {
        self.fileManager = fileManager
        if let searchPaths {
            self.searchPaths = searchPaths
            return
        }
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

    public func discoverApplications(showSystemApps: Bool) -> [DiscoveredApp] {
        lock.lock()
        defer { lock.unlock() }
        print("discover applications with : \(showSystemApps ? "include system apps" : "exclude system apps")")
        var applications: [String: DiscoveredApp] = [:]
        var discoveredPaths = Set<String>()

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
                discoveredPaths.insert(Self.canonicalPath(for: url))

                guard let app = cachedApp(from: url) else { continue }
                if !showSystemApps && app.isSystemApp {
                    continue
                }
                if applications[app.identifier] != nil {
                    continue
                }
                applications[app.identifier] = app
            }
        }

        cachedAppsByPath = cachedAppsByPath.filter { discoveredPaths.contains($0.key) }

        return Array(applications.values)
    }

    public func refreshApplications(changedPaths: [String], showSystemApps: Bool) -> [DiscoveredApp] {
        lock.lock()
        defer { lock.unlock() }

        guard !cachedAppsByPath.isEmpty else {
            lock.unlock()
            let result = discoverApplications(showSystemApps: showSystemApps)
            lock.lock()
            return result
        }

        for path in Set(changedPaths.compactMap(Self.applicationBundlePath(from:))) {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            let cacheKey = Self.canonicalPath(for: url)
            guard fileManager.fileExists(atPath: cacheKey) else {
                cachedAppsByPath.removeValue(forKey: cacheKey)
                continue
            }
            cachedAppsByPath.removeValue(forKey: cacheKey)
            _ = cachedApp(from: URL(fileURLWithPath: cacheKey, isDirectory: true))
        }

        var unique: [String: DiscoveredApp] = [:]
        for cached in cachedAppsByPath.values {
            let app = cached.app
            if !showSystemApps && app.isSystemApp { continue }
            unique[app.identifier] = unique[app.identifier] ?? app
        }
        return Array(unique.values)
    }

    static func applicationBundlePath(from eventPath: String) -> String? {
        let components = URL(fileURLWithPath: eventPath).pathComponents
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        let path = NSString.path(withComponents: Array(components.prefix(through: index)))
        return canonicalPath(for: URL(fileURLWithPath: path, isDirectory: true))
    }

    private static func canonicalPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func cachedApp(from url: URL) -> DiscoveredApp? {
        let cacheKey = Self.canonicalPath(for: url)
        let modificationDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let cached = cachedAppsByPath[cacheKey], cached.modificationDate == modificationDate {
            return cached.app
        }
        guard let app = makeApp(from: url) else { return nil }
        cachedAppsByPath[cacheKey] = CachedApp(modificationDate: modificationDate, app: app)
        return app
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

extension ApplicationDiscoveryService: @unchecked Sendable {}
