import XCTest
@testable import ManiculeCore

final class LauncherSpecTests: XCTestCase {
    private let docsID = WebApp.docs.chromeAppID
    private let sheetsID = WebApp.sheets.chromeAppID

    private func target(_ id: String, _ browser: Browser, _ profile: String?, _ name: String) -> Target {
        Target(id: id, browser: browser, profile: profile, name: name, email: nil)
    }
    private func profile(_ browser: Browser, _ dir: String, apps: Set<String>) -> DiscoveredProfile {
        DiscoveredProfile(browser: browser, directory: dir, name: dir, email: nil, installedWebApps: apps)
    }

    func testOneLauncherPerVisibleProfileAndInstalledApp() {
        let specs = LauncherSpecs.make(
            visible: [target("a", .chrome, "Profile 3", "Chrome · Work")],
            profiles: [profile(.chrome, "Profile 3", apps: [docsID, sheetsID])])
        XCTAssertEqual(specs.count, 2)
        XCTAssertEqual(specs.map(\.chromeAppID), [docsID, sheetsID])
    }

    func testHiddenTargetsGetNone() {
        let specs = LauncherSpecs.make(
            visible: [target("a", .chrome, "Default", "Chrome · Home")],
            profiles: [profile(.chrome, "Default", apps: [docsID]), profile(.chrome, "Profile 3", apps: [docsID])])
        XCTAssertEqual(specs.map(\.appName), ["Docs – Home"])
        XCTAssertTrue(LauncherSpecs.make(visible: [], profiles: [profile(.chrome, "Default", apps: [docsID])]).isEmpty)
    }

    func testNonChromeTargetsGetNone() {
        let specs = LauncherSpecs.make(
            visible: [target("f", .firefox, "x", "Firefox · x"), target("s", .safari, nil, "Safari")],
            profiles: [profile(.firefox, "x", apps: [docsID])])
        XCTAssertTrue(specs.isEmpty)
    }

    func testNamesAndBundleIDs() {
        let specs = LauncherSpecs.make(
            visible: [target("a", .chrome, "Profile 3", "Chrome · Work")],
            profiles: [profile(.chrome, "Profile 3", apps: [docsID])])
        XCTAssertEqual(specs, [LauncherSpec(
            appName: "Docs – Work",
            bundleID: "com.lockyc.manicule.launcher.docs.Profile-3",
            chromeAppID: docsID,
            command: Launch.webAppCommand(app: .docs, target: target("a", .chrome, "Profile 3", "Chrome · Work")))])
    }

    func testScriptQuotesSpacesAndSingleQuotes() {
        let cmd = LaunchCommand(executable: "/usr/bin/open", arguments: ["-na", "Google Chrome", "it's here"])
        XCTAssertEqual(LauncherSpecs.script(for: cmd),
                       "#!/bin/sh\nexec '/usr/bin/open' '-na' 'Google Chrome' 'it'\\''s here'\n")
    }
}
