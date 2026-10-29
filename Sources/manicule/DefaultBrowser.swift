import AppKit

/// The system default browser: which app holds it, and making it Manicule.
@MainActor
enum DefaultBrowser {
    /// The app that currently opens https links.
    static var current: URL? {
        NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https:")!)
    }

    static func name(of app: URL?) -> String {
        guard let app else { return "None" }
        let bundle = Bundle(url: app)
        return bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? app.deletingPathExtension().lastPathComponent
    }

    static func isManicule(_ app: URL?) -> Bool {
        guard let app, let ours = Bundle.main.bundleIdentifier else { return false }
        return Bundle(url: app)?.bundleIdentifier == ours
    }

    /// Asks macOS to make this app the handler for http, then https; macOS confirms with the user
    /// for each. `done` runs on the main actor with the first error, if any.
    static func makeManicule(done: @escaping @MainActor (Error?) -> Void) {
        let app = Bundle.main.bundleURL
        NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "http") { error in
            if let error {
                Task { @MainActor in done(error) }
                return
            }
            NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "https") { error in
                Task { @MainActor in done(error) }
            }
        }
    }
}
