import XCTest
@testable import ManiculeCore

final class LaunchCommandTests: XCTestCase {
    private let docsID = "mpnpojknpmmopombnjdcgaaiekajbnjb"
    private func target(_ b: Browser, _ p: String?) -> Target {
        Target(id: "t", browser: b, profile: p, name: "n", email: nil)
    }

    func testChromeProfileTab() {
        let c = Launch.command(for: URL(string: "https://example.com/a?b=1")!, target: target(.chrome, "Profile 3"), installedWebApps: [])
        XCTAssertEqual(c, LaunchCommand(executable: "/usr/bin/open", arguments:
            ["-na", "Google Chrome", "--args", "--profile-directory=Profile 3", "https://example.com/a?b=1"]))
    }

    func testChromeDocInInstalledWebApp() {
        let u = "https://docs.google.com/document/d/abc/edit"
        let t = target(.chrome, "Profile 3")
        XCTAssertEqual(Launch.command(for: URL(string: u)!, target: t, installedWebApps: [docsID]).arguments,
            ["-na", "Google Chrome", "--args", "--profile-directory=Profile 3", "--app-id=" + docsID,
             "--app-launch-url-for-shortcuts-menu-item=" + u])
        XCTAssertEqual(Launch.command(for: URL(string: u)!, target: t, installedWebApps: []).arguments,
            ["-na", "Google Chrome", "--args", "--profile-directory=Profile 3", u])
    }

    func testChromiumUsesChromiumApp() {
        let c = Launch.command(for: URL(string: "https://example.com")!, target: target(.chromium, "Default"), installedWebApps: [])
        XCTAssertEqual(Array(c.arguments.prefix(2)), ["-na", "Chromium"])
    }

    func testFirefoxProfile() {
        let u = URL(string: "https://example.com")!
        let c = Launch.command(for: u, target: target(.firefox, "Profiles/x.default-release"), installedWebApps: [],
                               firefoxApp: "/Apps/Firefox.app", firefoxRoot: "/Support/Firefox")
        XCTAssertEqual(c, LaunchCommand(executable: "/Apps/Firefox.app/Contents/MacOS/firefox", arguments:
            ["--profile", "/Support/Firefox/Profiles/x.default-release", "--new-tab", "https://example.com"]))
        let n = Launch.command(for: u, target: target(.firefox, nil), installedWebApps: [],
                               firefoxApp: "/Apps/Firefox.app", firefoxRoot: "/Support/Firefox")
        XCTAssertEqual(n.arguments, ["--new-tab", "https://example.com"])
    }

    func testSafari() {
        let c = Launch.command(for: URL(string: "https://example.com")!, target: target(.safari, nil), installedWebApps: [])
        XCTAssertEqual(c, LaunchCommand(executable: "/usr/bin/open", arguments: ["-a", "Safari", "https://example.com"]))
    }

    func testFlotillaByBundleID() {
        let c = Launch.command(for: URL(string: "https://drive.google.com/drive/folders/x")!, target: target(.flotilla, nil),
                               installedWebApps: [])
        XCTAssertEqual(c, LaunchCommand(executable: "/usr/bin/open",
                                        arguments: ["-b", "au.lsjc.flotilla", "https://drive.google.com/drive/folders/x"]))
    }

    func testWebAppCommand() {
        XCTAssertEqual(Launch.webAppCommand(app: .docs, target: target(.chrome, "Profile 3")).arguments,
            ["-na", "Google Chrome", "--args", "--profile-directory=Profile 3", "--app-id=" + docsID])
    }
}
