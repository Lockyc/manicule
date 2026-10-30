import AppKit

/// The menu bar's manicule: the app icon's hand, as a template image so the menu bar tints it.
/// Shapes are drawn in order, each cutting a gap around itself into those beneath it.
enum MenuBarIcon {
    /// The hand's shapes in the app icon's drawing units, cuff first; each is x, y, width, height,
    /// corner radius. The index finger is shorter than the app icon's to keep the item narrow.
    private static let shapes: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (0, 0, 120, 380, 24),      // cuff
        (110, 20, 350, 350, 120),  // palm
        (340, 20, 380, 104, 52),   // index finger
        (360, 136, 190, 92, 46),   // curled fingers
        (360, 240, 172, 92, 46),
        (330, 344, 150, 84, 42),
        (170, 136, 290, 92, 46),   // thumb
    ]
    private static let units = CGSize(width: 720, height: 428)

    static func image(height: CGFloat = 15, gap: CGFloat = 1) -> NSImage {
        let scale = height / units.height
        let size = NSSize(width: (units.width * scale).rounded(.up), height: height)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current else { return false }
            for (x, y, w, h, r) in shapes {
                let path = NSBezierPath(
                    roundedRect: NSRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale),
                    xRadius: r * scale, yRadius: r * scale)
                context.compositingOperation = .clear
                path.lineWidth = gap * 2
                path.stroke()
                context.compositingOperation = .sourceOver
                NSColor.black.setFill()
                path.fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Manicule"
        return image
    }
}
