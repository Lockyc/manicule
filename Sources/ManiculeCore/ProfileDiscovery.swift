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

    public static func discoverAll(home: URL) -> [DiscoveredProfile] {
        let support = home.appendingPathComponent("Library/Application Support")
        var result: [DiscoveredProfile] = []
        let chromiumRoots: [(Browser, String)] = [(.chrome, "Google/Chrome"), (.chromium, "Chromium")]
        for (browser, sub) in chromiumRoots {
            let dir = support.appendingPathComponent(sub)
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("Local State")),
                  let profiles = try? chromium(localState: data, browser: browser) else { continue }
            result += profiles.map { profile in
                var p = profile
                let apps = dir.appendingPathComponent(p.directory)
                    .appendingPathComponent("Web Applications/Manifest Resources")
                let names = (try? FileManager.default.contentsOfDirectory(atPath: apps.path)) ?? []
                p.installedWebApps = Set(names.filter { !$0.hasPrefix(".") })
                return p
            }
        }
        let ini = support.appendingPathComponent("Firefox/profiles.ini")
        if let text = try? String(contentsOf: ini, encoding: .utf8) {
            result += firefox(profilesINI: text)
        }
        result.append(DiscoveredProfile(browser: .safari, directory: "", name: "Safari",
                                        email: nil, installedWebApps: []))
        return result
    }
}
