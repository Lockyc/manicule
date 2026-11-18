import Foundation

/// One generated launcher app: opens a Chrome web app in one profile.
public struct LauncherSpec: Equatable, Sendable {
    public var appName: String
    public var bundleID: String
    public var chromeAppID: String
    public var command: LaunchCommand

    public init(appName: String, bundleID: String, chromeAppID: String, command: LaunchCommand) {
        self.appName = appName
        self.bundleID = bundleID
        self.chromeAppID = chromeAppID
        self.command = command
    }
}

extension WebApp {
    public var displayName: String {
        switch self {
        case .docs: "Docs"
        case .sheets: "Sheets"
        case .slides: "Slides"
        }
    }
}

public enum LauncherSpecs {
    /// Launcher bundle ids are `<prefix><app>.<browser>.<sanitised profile folder>`.
    static let bundleIDPrefix = "com.lockyc.manicule.launcher."

    /// The browser a launcher belongs to, read back from its bundle id.
    public static func browser(fromBundleID id: String) -> Browser? {
        guard id.hasPrefix(bundleIDPrefix) else { return nil }
        let parts = id.dropFirst(bundleIDPrefix.count).split(separator: ".")
        guard parts.count == 3 else { return nil }
        return Browser(rawValue: String(parts[1]))
    }

    /// One launcher per visible Chrome/Chromium target and web app installed in its profile. A
    /// launcher is named after the target's short name; its full name when another visible target
    /// shares that short name; and its full name and profile folder (with the browser when the
    /// folder is shared too) when another shares the full name. Names compare case-insensitively,
    /// as launcher file names do on disk.
    public static func make(visible: [Target], profiles: [DiscoveredProfile]) -> [LauncherSpec] {
        var specs: [LauncherSpec] = []
        let shortNames = Dictionary(grouping: visible, by: { $0.shortName.lowercased() })
        let fullNames = Dictionary(grouping: visible, by: { $0.name.lowercased() })
        for target in visible where target.browser == .chrome || target.browser == .chromium {
            guard let dir = target.profile,
                  let found = profiles.first(where: { $0.browser == target.browser && $0.directory == dir })
            else { continue }
            let sameName = fullNames[target.name.lowercased()] ?? []
            let name: String
            if (shortNames[target.shortName.lowercased()]?.count ?? 0) < 2 {
                name = target.shortName
            } else if sameName.count < 2 {
                name = target.name
            } else {
                let folderShared = sameName.filter { $0.profile == dir }.count > 1
                name = "\(target.name) (\(folderShared ? "\(target.browser.displayName) \(dir)" : dir))"
            }
            for app in [WebApp.docs, .sheets, .slides] where found.installedWebApps.contains(app.chromeAppID) {
                specs.append(LauncherSpec(
                    appName: "\(app.displayName) – \(name)",
                    bundleID: "\(bundleIDPrefix)\(app.rawValue).\(target.browser.rawValue).\(sanitise(dir))",
                    chromeAppID: app.chromeAppID,
                    command: Launch.webAppCommand(app: app, target: target)))
            }
        }
        return specs
    }

    /// The `/bin/sh` script that runs `command`, every word single-quoted.
    public static func script(for command: LaunchCommand) -> String {
        let words = ([command.executable] + command.arguments).map(quote).joined(separator: " ")
        return "#!/bin/sh\nexec \(words)\n"
    }

    private static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func sanitise(_ s: String) -> String {
        String(s.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") ? $0 : "-" })
    }
}
