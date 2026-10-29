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

    private static func load(_ target: Target, home: URL) -> NSImage {
        switch target.browser {
        case .chrome, .chromium:
            if let picture = profilePicture(target, home: home) { return picture }
            return initial(target)
        case .firefox, .safari:
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.browser.bundleID)
            else { return initial(target) }
            return NSWorkspace.shared.icon(forFile: app.path)
        }
    }

    /// Chrome and Chromium keep the signed-in account's avatar as a PNG in the profile directory.
    private static func profilePicture(_ target: Target, home: URL) -> NSImage? {
        let root = target.browser == .chrome ? "Google/Chrome" : "Chromium"
        let file = home.appendingPathComponent("Library/Application Support/\(root)")
            .appendingPathComponent(target.profile ?? "Default")
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

    /// FNV-1a over the id: `hashValue` is seeded per process, so it would change the colour each launch.
    static func hue(_ id: String) -> CGFloat {
        var hash: UInt32 = 2_166_136_261
        for byte in id.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return CGFloat(hash % 360) / 360
    }
}
