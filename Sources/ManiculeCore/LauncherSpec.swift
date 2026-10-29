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
    /// One launcher per visible Chrome/Chromium target and web app installed in its profile.
    public static func make(visible: [Target], profiles: [DiscoveredProfile]) -> [LauncherSpec] {
        var specs: [LauncherSpec] = []
        for target in visible where target.browser == .chrome || target.browser == .chromium {
            guard let dir = target.profile,
                  let found = profiles.first(where: { $0.browser == target.browser && $0.directory == dir })
            else { continue }
            for app in [WebApp.docs, .sheets, .slides] where found.installedWebApps.contains(app.chromeAppID) {
                specs.append(LauncherSpec(
                    appName: "\(app.displayName) – \(target.shortName)",
                    bundleID: "com.lockyc.manicule.launcher.\(app.rawValue).\(sanitise(dir))",
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
