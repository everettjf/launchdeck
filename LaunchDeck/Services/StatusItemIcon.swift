import AppKit

enum StatusItemIcon {
    static let size = NSSize(width: 18, height: 18)

    static func make(accessibilityDescription: String) -> NSImage {
        let image = NSImage(size: size, flipped: false) { bounds in
            NSGraphicsContext.current?.shouldAntialias = true
            NSColor.black.setStroke()

            let stroke = NSBezierPath()
            stroke.lineWidth = 1.45
            stroke.lineCapStyle = .round
            stroke.lineJoinStyle = .round

            // The deck and its two capture towers.
            stroke.move(to: NSPoint(x: 1.5, y: 2.5))
            stroke.line(to: NSPoint(x: 16.5, y: 2.5))
            stroke.move(to: NSPoint(x: 3, y: 2.5))
            stroke.line(to: NSPoint(x: 3, y: 13.5))
            stroke.line(to: NSPoint(x: 6.5, y: 11.5))
            stroke.move(to: NSPoint(x: 15, y: 2.5))
            stroke.line(to: NSPoint(x: 15, y: 13.5))
            stroke.line(to: NSPoint(x: 11.5, y: 11.5))

            // A descending reusable vehicle held above the launch deck.
            stroke.move(to: NSPoint(x: 7.25, y: 7))
            stroke.line(to: NSPoint(x: 7.25, y: 12.5))
            stroke.curve(to: NSPoint(x: 9, y: 16),
                         controlPoint1: NSPoint(x: 7.25, y: 14.1),
                         controlPoint2: NSPoint(x: 8.25, y: 15.4))
            stroke.curve(to: NSPoint(x: 10.75, y: 12.5),
                         controlPoint1: NSPoint(x: 9.75, y: 15.4),
                         controlPoint2: NSPoint(x: 10.75, y: 14.1))
            stroke.line(to: NSPoint(x: 10.75, y: 7))
            stroke.move(to: NSPoint(x: 7.25, y: 7))
            stroke.line(to: NSPoint(x: 9, y: 8.25))
            stroke.line(to: NSPoint(x: 10.75, y: 7))
            stroke.stroke()

            return bounds.size == size
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}
