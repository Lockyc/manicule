import XCTest
@testable import ManiculeCore

final class ProfileDiscoveryTests: XCTestCase {
    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("manicule-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        return home
    }

    private let localState = """
    {"profile":{"info_cache":{
      "Default":{"name":"Work","user_name":"a@example.com"},
      "Profile 3":{"name":"Home","user_name":""}}}}
    """

    func testChromeProfilesReadNameAndEmail() throws {
        let found = try ProfileDiscovery.chromium(localState: Data(localState.utf8), browser: .chrome)
        XCTAssertEqual(found.count, 2)
        let def = try XCTUnwrap(found.first { $0.directory == "Default" })
        XCTAssertEqual(def.name, "Work")
        XCTAssertEqual(def.email, "a@example.com")
        let p3 = try XCTUnwrap(found.first { $0.directory == "Profile 3" })
        XCTAssertEqual(p3.name, "Home")
        XCTAssertNil(p3.email)
        XCTAssertTrue(p3.installedWebApps.isEmpty)
    }

    func testInstalledWebAppsFromManifestResources() throws {
        let home = try makeHome()
        let chrome = home.appendingPathComponent("Library/Application Support/Google/Chrome")
        let apps = chrome.appendingPathComponent("Default/Web Applications/Manifest Resources/docsid123")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        try localState.write(to: chrome.appendingPathComponent("Local State"), atomically: true, encoding: .utf8)
        let found = ProfileDiscovery.discoverAll(home: home)
        XCTAssertEqual(found.first { $0.directory == "Default" }?.installedWebApps, ["docsid123"])
        XCTAssertEqual(found.first { $0.directory == "Profile 3" }?.installedWebApps, [])
    }

    func testFirefoxProfilesINI() {
        let ini = "[Profile0]\nName=default-release\nPath=Profiles/x.default-release\n"
        let found = ProfileDiscovery.firefox(profilesINI: ini)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].browser, .firefox)
        XCTAssertEqual(found[0].directory, "Profiles/x.default-release")
        XCTAssertEqual(found[0].name, "default-release")
    }

    func testDiscoverAllSkipsMissingBrowsers() throws {
        let found = ProfileDiscovery.discoverAll(home: try makeHome())
        XCTAssertEqual(found, [DiscoveredProfile(browser: .safari, directory: "", name: "Safari", email: nil, installedWebApps: [])])
    }
}
