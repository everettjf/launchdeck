import Foundation
import LaunchDeckCore

nonisolated struct LocalContentIndexer: Sendable {
    struct Configuration: Sendable {
        var roots: [URL]
        var maximumItems = 5_000
        var maximumDepth = 8
    }

    private static let ignoredDirectories: Set<String> = [
        ".git", ".build", ".swiftpm", "deriveddata", "node_modules", "pods", "carthage",
        ".trash"
    ]
    /// Only the user's own Library is skipped; a project folder that happens to be called
    /// "Library" is still indexed.
    private static let ignoredPaths: Set<String> = [
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").standardizedFileURL.path
    ]
    private static let documentExtensions: Set<String> = [
        "md", "txt", "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers",
        "key", "png", "jpg", "jpeg", "heic", "svg", "swift", "json", "yaml", "yml"
    ]
    private static let projectExtensions: Set<String> = ["xcodeproj", "xcworkspace", "playground"]

    func index(configuration: Configuration, recentURLs: [URL] = [],
               isCancelled: @Sendable () -> Bool = { false }) -> [SearchItem] {
        var found: [String: SearchItem] = [:]
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isHiddenKey, .nameKey]
        for root in configuration.roots where found.count < configuration.maximumItems {
            guard !isCancelled() else { return [] }
            guard root.isFileURL else { continue }
            let rootDepth = root.standardizedFileURL.pathComponents.count
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles], errorHandler: { _, _ in true }
            ) else { continue }

            if (try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                found[root.path] = item(root, kind: .folder, keywords: ["folder", "search root"])
            }

            while let url = enumerator.nextObject() as? URL, found.count < configuration.maximumItems {
                guard !isCancelled() else { return [] }
                let depth = url.standardizedFileURL.pathComponents.count - rootDepth
                if depth > configuration.maximumDepth {
                    enumerator.skipDescendants()
                    continue
                }
                let values = try? url.resourceValues(forKeys: Set(keys))
                let name = values?.name ?? url.lastPathComponent
                let loweredName = name.lowercased()
                if values?.isDirectory == true,
                   Self.ignoredDirectories.contains(loweredName) || Self.ignoredPaths.contains(url.standardizedFileURL.path) {
                    enumerator.skipDescendants()
                    continue
                }

                let ext = url.pathExtension.lowercased()
                if Self.projectExtensions.contains(ext) {
                    found[url.path] = item(url, kind: .project, keywords: ["project", "xcode"])
                    enumerator.skipDescendants()
                } else if values?.isDirectory == true, FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
                    found[url.path] = item(url, kind: .project, keywords: ["project", "git", "repository"])
                    enumerator.skipDescendants()
                } else if values?.isDirectory == true, depth == 1 {
                    found[url.path] = item(url, kind: .folder, keywords: ["folder"])
                } else if values?.isDirectory == false, Self.documentExtensions.contains(ext) {
                    found[url.path] = item(url, kind: .file, keywords: [ext, "document"])
                }
            }
        }
        for url in recentURLs where found.count < configuration.maximumItems && url.isFileURL {
            guard !isCancelled() else { return [] }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            let kind: SearchItemKind = isDirectory.boolValue ? .folder : .file
            found[url.path] = item(url, kind: kind, keywords: ["recent", kind.rawValue])
        }
        return found.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Classifies one path the way a full scan would, so a single changed file can be added to
    /// the index without rescanning. Returns nil when a scan would not include it.
    func item(for url: URL, roots: [URL], maximumDepth: Int = Configuration(roots: []).maximumDepth) -> SearchItem? {
        let path = url.standardizedFileURL.path
        guard let root = roots.map(\.standardizedFileURL).first(where: { path == $0.path || path.hasPrefix($0.path + "/") }) else {
            return nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        if path == root.path {
            return isDirectory.boolValue ? item(url, kind: .folder, keywords: ["folder", "search root"]) : nil
        }
        if Self.ignoredPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return nil }
        let relative = url.standardizedFileURL.pathComponents.dropFirst(root.pathComponents.count)
        guard relative.count <= maximumDepth,
              !relative.contains(where: { $0.hasPrefix(".") && $0 != "." }),
              !relative.dropLast().contains(where: { Self.ignoredDirectories.contains($0.lowercased())
                  || Self.projectExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }) else {
            return nil
        }
        let ext = url.pathExtension.lowercased()
        if Self.projectExtensions.contains(ext) { return item(url, kind: .project, keywords: ["project", "xcode"]) }
        if isDirectory.boolValue {
            if Self.ignoredDirectories.contains(url.lastPathComponent.lowercased()) { return nil }
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
                return item(url, kind: .project, keywords: ["project", "git", "repository"])
            }
            return relative.count == 1 ? item(url, kind: .folder, keywords: ["folder"]) : nil
        }
        return Self.documentExtensions.contains(ext) ? item(url, kind: .file, keywords: [ext, "document"]) : nil
    }

    /// The item a full scan adds for a recently opened document outside the indexed roots.
    func recentItem(for url: URL) -> SearchItem? {
        var isDirectory: ObjCBool = false
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        let kind: SearchItemKind = isDirectory.boolValue ? .folder : .file
        return item(url, kind: kind, keywords: ["recent", kind.rawValue])
    }

    private func item(_ url: URL, kind: SearchItemKind, keywords: [String]) -> SearchItem {
        let target: SearchItemTarget
        switch kind {
        case .project: target = .project(path: url.path)
        case .folder: target = .folder(path: url.path)
        default: target = .file(path: url.path)
        }
        return SearchItem(id: "\(kind.rawValue):\(url.standardizedFileURL.path)", kind: kind,
                          title: url.deletingPathExtension().lastPathComponent,
                          subtitle: url.deletingLastPathComponent().path,
                          keywords: keywords, target: target)
    }
}
