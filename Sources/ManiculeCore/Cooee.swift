import Foundation

/// One cooee profile as its manifest publishes it: `account` is the Google account it is signed
/// into, or nil.
public struct CooeeProfile: Decodable, Equatable, Sendable {
    public var name: String
    public var account: String?

    public init(name: String, account: String?) {
        self.name = name
        self.account = account
    }
}

/// cooee's profiles as targets, read from its manifest. A profile is a stored target, found like a
/// browser profile; plain `cooee|` hands a link to cooee's own profile choice. Ids are
/// `cooee|<profile>`, the name percent-encoded.
public enum Cooee {
    static let manifestVersion = 1
    public static let meetHost = "meet.google.com"
    private static let prefix = "\(Browser.cooee.rawValue)|"
    /// Plain cooee, which picks the profile itself.
    public static let plainID: Target.ID = prefix
    private static let namePrefix = Browser.cooee.displayName + Target.nameSeparator

    /// The file cooee rewrites whenever its profiles change.
    public static func manifest(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support")
            .appendingPathComponent(Browser.cooee.bundleID, isDirectory: true)
            .appendingPathComponent("profiles.json")
    }

    /// The manifest's profiles in cooee's order; none when the file is missing, unreadable,
    /// undecodable or another version. A profile that doesn't decode, or has an empty name, is
    /// left out, not the whole manifest.
    public static func load(from file: URL) -> [CooeeProfile] {
        struct Entry: Decodable {
            var profile: CooeeProfile?
            init(from decoder: Decoder) throws { profile = try? CooeeProfile(from: decoder) }
        }
        struct Manifest: Decodable {
            var version: Int
            var profiles: [Entry]
        }
        guard let data = try? Data(contentsOf: file),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.version == manifestVersion else { return [] }
        return manifest.profiles.compactMap(\.profile).filter { !$0.name.isEmpty }
    }

    public static func profileID(_ name: String) -> Target.ID {
        prefix + PercentEncoding.encode(name)
    }

    /// The profile a cooee id names; nil for plain `cooee|` and for any other id.
    public static func profileName(_ id: Target.ID) -> String? {
        guard id.hasPrefix(prefix),
              let name = String(id.dropFirst(prefix.count)).removingPercentEncoding,
              !name.isEmpty else { return nil }
        return name
    }

    /// A profile target's default name.
    static func profileDisplayName(_ name: String) -> String { namePrefix + name }

    /// The URL that hands `link` to cooee, aimed at the profile the target names; plain cooee
    /// gets no profile.
    static func joinURL(_ link: URL, target: Target) -> String {
        let query = [("profile", profileName(target.id)), ("url", link.absoluteString)]
            .compactMap { key, value in value.map { "\(key)=\(PercentEncoding.encode($0))" } }
        return "cooee://join?" + query.joined(separator: "&")
    }

    /// Whether `url` is an https Google Meet link, the only kind cooee opens.
    public static func isMeet(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == meetHost
    }
}

extension DiscoveredProfile {
    /// A cooee profile: its directory is the encoded name, so `targetID` is `Cooee.profileID(name)`.
    public init(cooee: CooeeProfile) {
        self.init(browser: .cooee, directory: PercentEncoding.encode(cooee.name),
                  name: cooee.name, email: cooee.account, installedWebApps: [])
    }
}
