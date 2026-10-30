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
        let found = ProfileDiscovery.discoverAll(home: home, installed: [])
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
        XCTAssertFalse(found[0].isDefault)
    }

    /// Firefox's own default is the profile its install section names; the legacy
    /// `Default=1` marks an older profile and loses to it.
    func testFirefoxDefaultIsTheInstallSectionsProfile() {
        let ini = """
        [Install4F96D1932A9F858E]
        Default=Profiles/b.default-release
        Locked=1

        [Profile1]
        Name=default
        IsRelative=1
        Path=Profiles/a.default
        Default=1

        [Profile0]
        Name=default-release
        IsRelative=1
        Path=Profiles/b.default-release

        [General]
        StartWithLastProfile=1
        """
        let found = ProfileDiscovery.firefox(profilesINI: ini)
        XCTAssertEqual(found.map(\.directory), ["Profiles/a.default", "Profiles/b.default-release"])
        XCTAssertEqual(found.map(\.isDefault), [false, true])
    }

    func testFirefoxDefaultFallsBackToDefaultOneWithoutAnInstallSection() {
        let ini = "[Profile0]\nName=a\nPath=Profiles/a\n\n[Profile1]\nName=b\nPath=Profiles/b\nDefault=1\n"
        XCTAssertEqual(ProfileDiscovery.firefox(profilesINI: ini).map(\.isDefault), [false, true])
    }

    func testDiscoverAllSkipsMissingBrowsers() throws {
        let found = ProfileDiscovery.discoverAll(home: try makeHome(), installed: [])
        XCTAssertEqual(found, [DiscoveredProfile(browser: .safari, directory: "", name: "Safari", email: nil, installedWebApps: [])])
    }

    func testFlotillaIsATargetOnlyWhenInstalled() throws {
        let found = ProfileDiscovery.discoverAll(home: try makeHome(), installed: [.flotilla])
        XCTAssertEqual(found.map(\.targetID), ["safari|", "flotilla|"])
    }
}

final class UnreadableRootsTests: XCTestCase {
    private var lockedFiles: [URL] = []

    override func tearDownWithError() throws {
        for file in lockedFiles {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        }
    }

    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("manicule-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        return home
    }

    func testUnreadableRootListedWhenFileUnreadable() throws {
        let home = try makeHome()
        let chrome = home.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
        try FileManager.default.createDirectory(at: chrome, withIntermediateDirectories: true)
        let file = chrome.appendingPathComponent("Local State")
        try Data("{}".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        lockedFiles.append(file)
        XCTAssertEqual(ProfileDiscovery.unreadableRoots(home: home),
                       [BrowserRoot(browser: .chrome, folder: chrome, profileFile: file)])
    }

    func testMissingBrowserIsNotUnreadable() throws {
        XCTAssertEqual(ProfileDiscovery.unreadableRoots(home: try makeHome()), [])
    }

    func testReadableAndFilelessRootsAreNotUnreadable() throws {
        let home = try makeHome()
        let support = home.appendingPathComponent("Library/Application Support")
        let firefox = support.appendingPathComponent("Firefox")
        try FileManager.default.createDirectory(at: firefox, withIntermediateDirectories: true)
        try Data("[Profile0]\n".utf8).write(to: firefox.appendingPathComponent("profiles.ini"))
        try FileManager.default.createDirectory(at: support.appendingPathComponent("Chromium"),
                                                withIntermediateDirectories: true)
        XCTAssertEqual(ProfileDiscovery.unreadableRoots(home: home), [])
    }
}
