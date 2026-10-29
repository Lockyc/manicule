import Foundation

public enum Browser: String, Codable, CaseIterable, Sendable {
    case chrome, chromium, firefox, safari

    public var displayName: String {
        switch self {
        case .chrome: "Chrome"
        case .chromium: "Chromium"
        case .firefox: "Firefox"
        case .safari: "Safari"
        }
    }

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

    /// The line under a picker tile's name, for tiles whose short name another tile shares: the
    /// account email, else the profile folder.
    public static func tileDetails(_ strip: [Target]) -> [Target.ID: String] {
        let counts = Dictionary(grouping: strip, by: \.shortName).mapValues(\.count)
        var details: [Target.ID: String] = [:]
        for target in strip where counts[target.shortName, default: 0] > 1 {
            details[target.id] = target.email ?? target.profile ?? target.browser.displayName
        }
        return details
    }

    /// `id` and `browser` are required; a missing name is the browser's.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let browser = try c.decode(Browser.self, forKey: .browser)
        self.init(id: try c.decode(String.self, forKey: .id), browser: browser,
                  profile: try c.decodeIfPresent(String.self, forKey: .profile),
                  name: try c.decodeIfPresent(String.self, forKey: .name) ?? browser.displayName,
                  email: try c.decodeIfPresent(String.self, forKey: .email))
    }

    /// Joins a browser to a profile name in default target names ("Chrome · Work").
    public static let nameSeparator = " · "

    /// The name without a leading "<Browser> · ", for space-tight places like a picker tile.
    public var shortName: String {
        guard let range = name.range(of: Self.nameSeparator) else { return name }
        let rest = name[range.upperBound...]
        return rest.isEmpty ? name : String(rest)
    }
}

public struct DiscoveredProfile: Equatable, Sendable {
    public var browser: Browser
    public var directory: String
    public var name: String
    public var email: String?
    public var installedWebApps: Set<String>
    /// The browser's own default profile (Firefox's install default).
    public var isDefault: Bool

    public init(browser: Browser, directory: String, name: String, email: String?, installedWebApps: Set<String>,
                isDefault: Bool = false) {
        self.browser = browser
        self.directory = directory
        self.name = name
        self.email = email
        self.installedWebApps = installedWebApps
        self.isDefault = isDefault
    }

    /// The id of the target this profile becomes.
    public var targetID: Target.ID { "\(browser.rawValue)|\(directory)" }
}
