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
        ".trash", "library"
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
                if values?.isDirectory == true, Self.ignoredDirectories.contains(loweredName) {
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
