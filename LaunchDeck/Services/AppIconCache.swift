import AppKit

@MainActor
final class AppIconCache {
    typealias Loader = @Sendable (String, CGFloat) async -> NSImage

    static let shared = AppIconCache()

    private let cache = NSCache<NSString, NSImage>()
    private var pending: [String: [(NSImage) -> Void]] = [:]
    private let loader: Loader

    init(loader: @escaping Loader = { path, size in
        await Task.detached(priority: .userInitiated) {
            AppIconCache.fetchIcon(path: path, size: size)
        }.value
    }) {
        self.loader = loader
        cache.countLimit = 512
        cache.totalCostLimit = 64 * 1_024 * 1_024
    }

    func icon(for path: String, size: CGFloat, completion: @escaping (NSImage) -> Void) {
        let key = cacheKey(path: path, size: size)
        if let cached = cache.object(forKey: key as NSString) {
            completion(cached)
            return
        }

        if pending[key] != nil {
            pending[key, default: []].append(completion)
            return
        }
        pending[key] = [completion]

        Task {
            let image = await loader(path, size)
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let pixels = max(1, Int(size * scale))
            cache.setObject(image, forKey: key as NSString, cost: pixels * pixels * 4)
            let completions = pending.removeValue(forKey: key) ?? []
            completions.forEach { $0(image) }
        }
    }

    func invalidate(path: String) {
        // NSCache does not expose its keys, so clearing is the only reliable way
        // to avoid retaining a stale application icon after a bundle update.
        cache.removeAllObjects()
        pending = pending.filter { !$0.key.hasPrefix("\(path)#") }
    }

    func removeAll() {
        cache.removeAllObjects()
        pending.removeAll()
    }

    nonisolated private static func fetchIcon(path: String, size: CGFloat) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: size, height: size)
        return image
    }

    private func cacheKey(path: String, size: CGFloat) -> String {
        "\(path)#\(Int(size * (NSScreen.main?.backingScaleFactor ?? 2)))"
    }
}
