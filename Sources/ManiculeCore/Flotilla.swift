import Foundation

/// One flotilla window as its manifest publishes it: groups in sidebar order, `colour` a CSS hex
/// colour or nil.
public struct FlotillaWindow: Decodable, Equatable, Sendable {
    public var title: String
    public var colour: String?
    public var groups: [String]

    public init(title: String, colour: String?, groups: [String]) {
        self.title = title
        self.colour = colour
        self.groups = groups
    }

    /// `title` is required; missing `colour` or `groups` take nil and none.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(title: try c.decode(String.self, forKey: .title),
                  colour: try c.decodeIfPresent(String.self, forKey: .colour),
                  groups: try c.decodeIfPresent([String].self, forKey: .groups) ?? [])
    }

    private enum CodingKeys: String, CodingKey { case title, colour, groups }
}

/// flotilla's windows and groups as targets. A window is a stored target, found like a browser
/// profile; a group is read fresh from the manifest on each routing and never stored. Ids are
/// `flotilla|<window>` and `flotilla|<window>|<group>`, each part percent-encoded so a `|` in a
/// title can't split it.
public enum Flotilla {
    static let manifestVersion = 1
    /// Joins a group to its window in a group target's name ("flotilla · Rotary ▸ Bulletins").
    static let groupSeparator = " ▸ "
    /// Ends the name of a remembered group that flotilla no longer has.
    static let closedSuffix = " (closed)"
    /// The only characters left bare in an id part or a URL value.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    private static let prefix = "\(Browser.flotilla.rawValue)|"
    /// Plain flotilla, which hands a link to its last focused window.
    static let plainID: Target.ID = prefix
    private static let namePrefix = Browser.flotilla.displayName + Target.nameSeparator

    /// The file flotilla rewrites whenever its windows change.
    public static func manifest(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support")
            .appendingPathComponent(Browser.flotilla.bundleID, isDirectory: true)
            .appendingPathComponent("windows.json")
    }

    /// The manifest's windows in flotilla's config order; none when the file is missing,
    /// unreadable, undecodable or another version. A window that doesn't decode is left out, not
    /// the whole manifest. An empty title or group name can't be told apart from its absence in
    /// an id, so it is left out too.
    public static func load(from file: URL) -> [FlotillaWindow] {
        struct Entry: Decodable {
            var window: FlotillaWindow?
            init(from decoder: Decoder) throws { window = try? FlotillaWindow(from: decoder) }
        }
        struct Manifest: Decodable {
            var version: Int
            var windows: [Entry]
        }
        guard let data = try? Data(contentsOf: file),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.version == manifestVersion else { return [] }
        return manifest.windows.compactMap(\.window).filter { !$0.title.isEmpty }.map { window in
            var w = window
            w.groups.removeAll(where: \.isEmpty)
            return w
        }
    }

    public static func windowID(_ title: String) -> Target.ID {
        prefix + encode(title)
    }

    public static func groupID(window: String, group: String) -> Target.ID {
        prefix + encode(window) + "|" + encode(group)
    }

    /// The window and group a flotilla id names; both nil for plain `flotilla|` and for any
    /// other id.
    public static func parse(_ id: Target.ID) -> (window: String?, group: String?) {
        guard id.hasPrefix(prefix) else { return (nil, nil) }
        let parts = id.dropFirst(prefix.count).split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.removingPercentEncoding.flatMap { $0.isEmpty ? nil : $0 } }
        switch parts.count {
        case 1: return (parts[0], nil)
        case 2: return (parts[0], parts[1])
        default: return (nil, nil)
        }
    }

    /// Every window's groups, windows in manifest order and groups in sidebar order; a group
    /// whose id repeats an earlier one (the same name twice in a window) is left out.
    public static func groupTargets(_ windows: [FlotillaWindow]) -> [Target] {
        var seen = Set<Target.ID>()
        return windows.flatMap { window in
            window.groups.map { group in
                Target(id: groupID(window: window.title, group: group), browser: .flotilla, profile: nil,
                       name: groupName(window: window.title, group: group), email: nil, colour: window.colour)
            }
        }
        .filter { seen.insert($0.id).inserted }
    }

    /// A window target's default name.
    static func windowName(_ title: String) -> String { namePrefix + title }

    static func groupName(window: String, group: String) -> String {
        namePrefix + window + groupSeparator + group
    }

    /// The URL that hands `link` to flotilla, aimed at the window and group the target names;
    /// nil for plain `flotilla|` and for an id naming no window (a group means nothing without
    /// one), which take the link as it is.
    static func openURL(_ link: URL, target: Target) -> String? {
        let (window, group) = parse(target.id)
        guard window != nil else { return nil }
        let query = [("window", window), ("group", group), ("url", link.absoluteString)]
            .compactMap { key, value in value.map { "\(key)=\(encode($0))" } }
        return "flotilla://open?" + query.joined(separator: "&")
    }

    static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
    }
}

extension DiscoveredProfile {
    /// A flotilla window as a profile: its directory is the encoded title, so `targetID` is
    /// `Flotilla.windowID(title)`.
    public init(window: FlotillaWindow) {
        self.init(browser: .flotilla, directory: Flotilla.encode(window.title),
                  name: window.title, email: nil, installedWebApps: [], colour: window.colour)
    }
}
