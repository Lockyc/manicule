import Foundation

public struct LaunchCommand: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

public enum Launch {
    static let open = "/usr/bin/open"

    /// The command that opens `url` in `target`. The URL is passed through unaltered.
    /// Firefox is launched through its own binary: it hands the URL to an already-running
    /// instance of that profile, where `open -na` would start a second instance.
    public static func command(
        for url: URL,
        target: Target,
        installedWebApps: Set<String>,
        firefoxApp: String = "/Applications/Firefox.app",
        firefoxRoot: String = ProfileDiscovery.folder(of: .firefox, home: URL(fileURLWithPath: NSHomeDirectory()))!.path
    ) -> LaunchCommand {
        let link = url.absoluteString
        switch target.browser {
        case .safari:
            return LaunchCommand(executable: open, arguments: ["-a", "Safari", link])
        case .firefox:
            var args: [String] = []
            if let profile = target.profile, !profile.isEmpty {
                args += ["--profile", firefoxRoot + "/" + profile]
            }
            args += ["--new-tab", link]
            return LaunchCommand(executable: firefoxApp + "/Contents/MacOS/firefox", arguments: args)
        case .chrome, .chromium:
            var cmd = chromeBase(target)
            if let app = GoogleLink(url: url)?.webApp, installedWebApps.contains(app.chromeAppID) {
                cmd.arguments += ["--app-id=" + app.chromeAppID,
                                  "--app-launch-url-for-shortcuts-menu-item=" + link]
            } else {
                cmd.arguments.append(link)
            }
            return cmd
        }
    }

    /// Opens the installed web app itself, without a document.
    public static func webAppCommand(app: WebApp, target: Target) -> LaunchCommand {
        var cmd = chromeBase(target)
        cmd.arguments.append("--app-id=" + app.chromeAppID)
        return cmd
    }

    private static func chromeBase(_ target: Target) -> LaunchCommand {
        var args = ["-na", target.browser == .chromium ? "Chromium" : "Google Chrome", "--args"]
        if let profile = target.profile, !profile.isEmpty {
            args.append("--profile-directory=" + profile)
        }
        return LaunchCommand(executable: open, arguments: args)
    }
}
