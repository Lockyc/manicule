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

    public static func firefox(profilesINI: String) -> [DiscoveredProfile] {
        var result: [DiscoveredProfile] = []
        var inProfile = false
        var name: String?
        var path: String?
        func flush() {
            if inProfile, let name, let path {
                result.append(DiscoveredProfile(browser: .firefox, directory: path, name: name,
                                                email: nil, installedWebApps: []))
            }
            name = nil
            path = nil
        }
        for raw in profilesINI.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                flush()
                inProfile = line.hasPrefix("[Profile")
            } else if let eq = line.firstIndex(of: "=") {
                let value = String(line[line.index(after: eq)...])
                switch line[..<eq] {
                case "Name": name = value
                case "Path": path = value
                default: break
                }
            }
        }
        flush()
        return result
    }

    /// Every browser whose profiles live in a file: Chrome, Chromium, Firefox (Safari has none).
    public static func roots(home: URL) -> [BrowserRoot] {
        let support = home.appendingPathComponent("Library/Application Support")
        return [(Browser.chrome, "Google/Chrome", "Local State"), (.chromium, "Chromium", "Local State"),
                (.firefox, "Firefox", "profiles.ini")].map { browser, sub, file in
            let folder = support.appendingPathComponent(sub, isDirectory: true)
            return BrowserRoot(browser: browser, folder: folder, profileFile: folder.appendingPathComponent(file))
        }
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

    public static func discoverAll(home: URL) -> [DiscoveredProfile] {
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
            case .safari:
                continue
            }
        }
        result.append(DiscoveredProfile(browser: .safari, directory: "", name: "Safari",
                                        email: nil, installedWebApps: []))
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
