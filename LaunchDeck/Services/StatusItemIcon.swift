import AppKit

enum StatusItemIcon {
    static let size = NSSize(width: 18, height: 18)

    static func make(accessibilityDescription: String) -> NSImage {
        let image = NSImage(size: size, flipped: false) { bounds in
            NSGraphicsContext.current?.shouldAntialias = true
            NSColor.black.setFill()

            // A compact, pixel-grid interpretation of the app icon. The image
            // remains a monochrome template so macOS can tint it correctly for
            // every menu-bar appearance and selection state.
            let pixels = NSBezierPath()

            // The stronger base deck and two mirrored capture brackets.
            pixels.appendRect(NSRect(x: 2, y: 2, width: 14, height: 2))
            pixels.appendRect(NSRect(x: 3, y: 4, width: 2, height: 9))
            pixels.appendRect(NSRect(x: 13, y: 4, width: 2, height: 9))
            pixels.appendRect(NSRect(x: 3, y: 12, width: 4, height: 2))
            pixels.appendRect(NSRect(x: 11, y: 12, width: 4, height: 2))
            pixels.appendRect(NSRect(x: 6, y: 10, width: 2, height: 2))
            pixels.appendRect(NSRect(x: 10, y: 10, width: 2, height: 2))

            // The enlarged suspended core: abstract and deliberately not a
            // literal rocket silhouette.
            pixels.appendRect(NSRect(x: 7, y: 7, width: 4, height: 4))
            pixels.appendRect(NSRect(x: 8, y: 6, width: 2, height: 1))
            pixels.appendRect(NSRect(x: 8, y: 11, width: 2, height: 1))
            pixels.fill()

            return bounds.size == size
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}
