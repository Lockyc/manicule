import Foundation

public enum ProfileDiscovery {
    public static func chromium(localState: Data, browser: Browser) throws -> [DiscoveredProfile] {
        let root = try JSONSerialization.jsonObject(with: localState) as? [String: Any]
        let cache = (root?["profile"] as? [String: Any])?["info_cache"] as? [String: Any] ?? [:]
        return cache.keys.sorted().map { dir in
            let info = cache[dir] as? [String: Any] ?? [:]
            let email = (info["user_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return DiscoveredProfile(browser: browser, directory: dir,
                                     name: info["name"] as? String ?? dir,
                                     email: email, installedWebApps: [])
        }
    }

    /// Profiles in file order. The default is the profile an `[Install…]` section's `Default=`
    /// names (Firefox's current default); a profile's own `Default=1` counts only when the file
    /// has no install section.
    public static func firefox(profilesINI: String) -> [DiscoveredProfile] {
        var result: [DiscoveredProfile] = []
        var legacyDefault: String?
        var installDefault: String?
        var section = ""
        var name: String?
        var path: String?
        var isDefault = false
        func flush() {
            if section.hasPrefix("[Profile"), let name, let path {
                result.append(DiscoveredProfile(browser: .firefox, directory: path, name: name,
                                                email: nil, installedWebApps: []))
                if isDefault { legacyDefault = path }
            }
            name = nil
            path = nil
            isDefault = false
        }
        for raw in profilesINI.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                flush()
                section = line
            } else if let eq = line.firstIndex(of: "=") {
                let key = line[..<eq]
                let value = String(line[line.index(after: eq)...])
                if section.hasPrefix("[Install") {
                    if key == "Default", installDefault == nil { installDefault = value }
                    continue
                }
                switch key {
                case "Name": name = value
                case "Path": path = value
                case "Default": isDefault = value == "1"
                default: break
                }
            }
        }
        flush()
        if let chosen = installDefault ?? legacyDefault {
            for i in result.indices where result[i].directory == chosen { result[i].isDefault = true }
        }
        return result
    }

    /// Every browser whose profiles live in a file: Chrome, Chromium, Firefox (Safari has none).
    public static func roots(home: URL) -> [BrowserRoot] {
        [(Browser.chrome, "Local State"), (.chromium, "Local State"), (.firefox, "profiles.ini")].compactMap { browser, file in
            folder(of: browser, home: home).map {
                BrowserRoot(browser: browser, folder: $0, profileFile: $0.appendingPathComponent(file))
            }
        }
    }

    /// The folder holding a browser's profiles; nil for Safari and flotilla, which have no profile folders.
    public static func folder(of browser: Browser, home: URL) -> URL? {
        let sub: String
        switch browser {
        case .chrome: sub = "Google/Chrome"
        case .chromium: sub = "Chromium"
        case .firefox: sub = "Firefox"
        case .safari, .flotilla: return nil
        }
        return home.appendingPathComponent("Library/Application Support").appendingPathComponent(sub, isDirectory: true)
    }

    /// Installed browsers whose profile file exists but can't be read — macOS withholds it until
    /// the user picks the folder in an open panel. A folder without the file is not listed:
    /// granting access would not make a missing file appear.
    public static func unreadableRoots(home: URL) -> [BrowserRoot] {
        roots(home: home).filter { root in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.folder.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return false }
            do {
                _ = try Data(contentsOf: root.profileFile)
                return false
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                return false
            } catch {
                return true
            }
        }
    }

    /// Every profile in the browsers' profile files, then Safari, then flotilla and its windows
    /// when `installed` holds it (Safari ships with macOS; flotilla may be absent).
    public static func discoverAll(home: URL, installed: Set<Browser>) -> [DiscoveredProfile] {
        var result: [DiscoveredProfile] = []
        for root in roots(home: home) {
            switch root.browser {
            case .chrome, .chromium:
                guard let data = try? Data(contentsOf: root.profileFile),
                      let profiles = try? chromium(localState: data, browser: root.browser) else { continue }
                result += profiles.map { profile in
                    var p = profile
                    let apps = root.folder.appendingPathComponent(p.directory)
                        .appendingPathComponent("Web Applications/Manifest Resources")
                    let names = (try? FileManager.default.contentsOfDirectory(atPath: apps.path)) ?? []
                    p.installedWebApps = Set(names.filter { !$0.hasPrefix(".") })
                    return p
                }
            case .firefox:
                if let text = try? String(contentsOf: root.profileFile, encoding: .utf8) {
                    result += firefox(profilesINI: text)
                }
            case .safari, .flotilla:
                continue
            }
        }
        result.append(DiscoveredProfile(browser: .safari, directory: "", name: "Safari",
                                        email: nil, installedWebApps: []))
        if installed.contains(.flotilla) {
            result.append(DiscoveredProfile(browser: .flotilla, directory: "", name: Browser.flotilla.displayName,
                                            email: nil, installedWebApps: []))
            result += Flotilla.load(from: Flotilla.manifest(home: home)).map(DiscoveredProfile.init(window:))
        }
        return result
    }
}

/// Where one browser keeps its profile list.
public struct BrowserRoot: Equatable, Sendable {
    public var browser: Browser
    public var folder: URL
    public var profileFile: URL

    public init(browser: Browser, folder: URL, profileFile: URL) {
        self.browser = browser
        self.folder = folder
        self.profileFile = profileFile
    }
}
