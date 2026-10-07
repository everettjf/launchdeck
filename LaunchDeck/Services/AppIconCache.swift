import AppKit

@MainActor
final class AppIconCache {
    typealias Loader = @Sendable (String, CGFloat) async -> NSImage

    static let shared = AppIconCache()

    private let cache = NSCache<NSString, NSImage>()
    private var pending: [String: [(NSImage) -> Void]] = [:]
    private var keysByPath: [String: Set<String>] = [:]
    private var generations: [String: Int] = [:]
    private var epoch = 0
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
        load(path: path, size: size, key: key)
    }

    /// Evicts one bundle's icons. Callers already waiting keep waiting and receive the
    /// reloaded icon; the in-flight load that started before the update is discarded.
    func invalidate(path: String) {
        generations[path, default: 0] += 1
        for key in keysByPath.removeValue(forKey: path) ?? [] {
            cache.removeObject(forKey: key as NSString)
        }
    }

    func removeAll() {
        epoch += 1
        cache.removeAllObjects()
        keysByPath.removeAll()
    }

    private struct Generation: Equatable {
        let epoch: Int
        let path: Int
    }

    private func generation(for path: String) -> Generation {
        Generation(epoch: epoch, path: generations[path, default: 0])
    }

    private func load(path: String, size: CGFloat, key: String) {
        let startedGeneration = generation(for: path)
        Task {
            let image = await loader(path, size)
            guard generation(for: path) == startedGeneration else {
                // The bundle changed while this load ran: the image may be stale.
                if pending[key] != nil { load(path: path, size: size, key: key) }
                return
            }
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let pixels = max(1, Int(size * scale))
            cache.setObject(image, forKey: key as NSString, cost: pixels * pixels * 4)
            keysByPath[path, default: []].insert(key)
            let completions = pending.removeValue(forKey: key) ?? []
            completions.forEach { $0(image) }
        }
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
