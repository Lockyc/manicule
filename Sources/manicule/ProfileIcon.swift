import AppKit
import ManiculeCore

/// A target's picture for the picker strip, cached per target id for the life of the app.
@MainActor
enum ProfileIcon {
    private static var cache: [Target.ID: NSImage] = [:]

    static func image(for target: Target, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> NSImage {
        if let cached = cache[target.id] { return cached }
        let image = load(target, home: home)
        cache[target.id] = image
        return image
    }

    /// Loads the pictures ahead of the first picker, so its strip appears without file reads.
    static func prewarm(_ targets: [Target]) {
        for target in targets { _ = image(for: target) }
    }

    static func isCached(_ id: Target.ID) -> Bool { cache[id] != nil }

    private static func load(_ target: Target, home: URL) -> NSImage {
        switch target.browser {
        case .chrome, .chromium:
            if let picture = profilePicture(target, home: home) { return picture }
            return initial(target)
        case .firefox, .safari, .flotilla:
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.browser.bundleID)
            else { return initial(target) }
            return NSWorkspace.shared.icon(forFile: app.path)
        }
    }

    /// Chrome and Chromium keep the signed-in account's avatar as a PNG in the profile directory.
    private static func profilePicture(_ target: Target, home: URL) -> NSImage? {
        guard let folder = ProfileDiscovery.folder(of: target.browser, home: home) else { return nil }
        let file = folder.appendingPathComponent(target.profile ?? "Default")
            .appendingPathComponent("Google Profile Picture.png")
        guard let picture = NSImage(contentsOf: file) else { return nil }
        return circular(picture)
    }

    private static let side: CGFloat = 96

    private static func circular(_ picture: NSImage) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSBezierPath(ovalIn: rect).addClip()
            picture.draw(in: rect)
            return true
        }
    }

    /// A circle in a colour fixed by the target id, carrying the short name's first letter.
    private static func initial(_ target: Target) -> NSImage {
        let letter = target.shortName.first.map { String($0).uppercased() } ?? "?"
        let colour = NSColor(hue: hue(target.id), saturation: 0.55, brightness: 0.78, alpha: 1)
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            colour.setFill()
            NSBezierPath(ovalIn: rect).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: side * 0.46, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
            let text = NSAttributedString(string: letter, attributes: attributes)
            let size = text.size()
            text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            return true
        }
    }

    /// FNV-1a over the id, then murmur3's finaliser: `hashValue` is seeded per process (the colour
    /// would change each launch), and plain FNV's low bits barely move for ids that differ only in
    /// their last character ("Profile 2", "Profile 3"), which would give neighbours the same hue.
    static func hue(_ id: String) -> CGFloat {
        var hash: UInt32 = 2_166_136_261
        for byte in id.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        hash ^= hash >> 16
        hash = hash &* 0x85EB_CA6B
        hash ^= hash >> 13
        hash = hash &* 0xC2B2_AE35
        hash ^= hash >> 16
        return CGFloat(hash % 360) / 360
    }
}
