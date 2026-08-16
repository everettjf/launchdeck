import AppKit

@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    private let cache = NSCache<NSString, NSImage>()

    func icon(for path: String, size: CGFloat, completion: @escaping (NSImage) -> Void) {
        let key = cacheKey(path: path, size: size)
        if let cached = cache.object(forKey: key as NSString) {
            completion(cached)
            return
        }

        Task {
            // NSWorkspace icon loading off the main actor; NSCache is thread-safe
            let image = await Task.detached(priority: .userInitiated) {
                Self.fetchIcon(path: path, size: size)
            }.value
            cache.setObject(image, forKey: key as NSString)
            completion(image)
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
