import Foundation

public enum Browser: String, Codable, CaseIterable, Sendable {
    case chrome, chromium, firefox, safari

    public var bundleID: String {
        switch self {
        case .chrome: "com.google.Chrome"
        case .chromium: "org.chromium.Chromium"
        case .firefox: "org.mozilla.firefox"
        case .safari: "com.apple.Safari"
        }
    }
}

public struct Target: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var browser: Browser
    public var profile: String?
    public var name: String
    public var email: String?

    public init(id: String, browser: Browser, profile: String?, name: String, email: String?) {
        self.id = id
        self.browser = browser
        self.profile = profile
        self.name = name
        self.email = email
    }
}

public struct DiscoveredProfile: Equatable, Sendable {
    public var browser: Browser
    public var directory: String
    public var name: String
    public var email: String?
    public var installedWebApps: Set<String>

    public init(browser: Browser, directory: String, name: String, email: String?, installedWebApps: Set<String>) {
        self.browser = browser
        self.directory = directory
        self.name = name
        self.email = email
        self.installedWebApps = installedWebApps
    }
}
