import AppKit

final class AppIconCache {
    static let shared = AppIconCache()

    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "app-icon-cache", qos: .userInitiated)

    func icon(for path: String, size: CGFloat, completion: @escaping (NSImage) -> Void) {
        let key = cacheKey(path: path, size: size)
        if let cached = cache.object(forKey: key as NSString) {
            completion(cached)
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            let image = NSWorkspace.shared.icon(forFile: path)
            image.size = NSSize(width: size, height: size)
            self.cache.setObject(image, forKey: key as NSString)
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    private func cacheKey(path: String, size: CGFloat) -> String {
        "\(path)#\(Int(size * (NSScreen.main?.backingScaleFactor ?? 2)))"
    }
}
