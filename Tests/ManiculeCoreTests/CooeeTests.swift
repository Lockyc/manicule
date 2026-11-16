import XCTest
@testable import ManiculeCore

final class CooeeTests: XCTestCase {
    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("manicule-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        return home
    }

    private func write(_ json: String, home: URL) throws {
        let file = Cooee.manifest(home: home)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json.write(to: file, atomically: true, encoding: .utf8)
    }

    func testManifestIsInCooeesApplicationSupport() {
        XCTAssertEqual(Cooee.manifest(home: URL(fileURLWithPath: "/Users/x")).path,
                       "/Users/x/Library/Application Support/au.lsjc.cooee/profiles.json")
    }

    func testManifestLoadsProfilesInOrder() throws {
        let home = try makeHome()
        try write(#"{"version":1,"profiles":[{"name":"work","account":"me@example.com"},{"name":"home","account":null}]}"#,
                  home: home)
        XCTAssertEqual(Cooee.load(from: Cooee.manifest(home: home)),
                       [CooeeProfile(name: "work", account: "me@example.com"), CooeeProfile(name: "home", account: nil)])
    }

    func testMissingBadOrOtherVersionManifestIsNothing() throws {
        let home = try makeHome()
        let file = Cooee.manifest(home: home)
        XCTAssertEqual(Cooee.load(from: file), [], "missing")
        try write("{not json", home: home)
        XCTAssertEqual(Cooee.load(from: file), [], "undecodable")
        try write(#"{"version":2,"profiles":[{"name":"a","account":null}]}"#, home: home)
        XCTAssertEqual(Cooee.load(from: file), [], "another version")
    }

    func testOddProfileDoesNotHideTheRest() throws {
        let home = try makeHome()
        try write(#"{"version":1,"profiles":[{"name":"a"},{"account":"x"},{"name":""},{"name":"b"}]}"#, home: home)
        XCTAssertEqual(Cooee.load(from: Cooee.manifest(home: home)).map(\.name), ["a", "b"])
    }

    func testProfileIDRoundTrips() {
        XCTAssertEqual(Cooee.profileName(Cooee.profileID("Work & Play")), "Work & Play")
        XCTAssertNil(Cooee.profileName(Cooee.plainID))
        XCTAssertNil(Cooee.profileName("chrome|Default"))
    }

    func testJoinURLEncodesProfileAndLink() {
        let link = URL(string: "https://meet.google.com/abc-defg-hij?authuser=me@example.com")!
        let t = Target(id: Cooee.profileID("Work & Play"), browser: .cooee, profile: nil, name: "x", email: nil)
        XCTAssertEqual(Cooee.joinURL(link, target: t),
            "cooee://join?profile=Work%20%26%20Play&url=https%3A%2F%2Fmeet.google.com%2Fabc-defg-hij%3Fauthuser%3Dme%40example.com")
        let plain = Target(id: Cooee.plainID, browser: .cooee, profile: nil, name: "cooee", email: nil)
        XCTAssertEqual(Cooee.joinURL(link, target: plain),
            "cooee://join?url=https%3A%2F%2Fmeet.google.com%2Fabc-defg-hij%3Fauthuser%3Dme%40example.com")
    }

    func testIsMeet() {
        XCTAssertTrue(Cooee.isMeet(URL(string: "https://meet.google.com/abc")!))
        XCTAssertTrue(Cooee.isMeet(URL(string: "https://MEET.google.com/abc")!))
        XCTAssertFalse(Cooee.isMeet(URL(string: "https://docs.google.com/abc")!))
        XCTAssertFalse(Cooee.isMeet(URL(string: "https://meet.google.com.evil.example/abc")!))
    }

    func testDiscoveryAddsCooeeWhenInstalled() throws {
        let home = try makeHome()
        try write(#"{"version":1,"profiles":[{"name":"work","account":"me@example.com"}]}"#, home: home)
        let found = ProfileDiscovery.discoverAll(home: home, installed: [.cooee])
        XCTAssertEqual(found.filter { $0.browser == .cooee }.map(\.targetID), ["cooee|", "cooee|work"])
        XCTAssertEqual(found.last?.email, "me@example.com")
        XCTAssertTrue(ProfileDiscovery.discoverAll(home: home, installed: []).allSatisfy { $0.browser != .cooee })
    }

    func testDefaultsNameCooeeTargets() throws {
        let config = Config.defaults(from: [
            DiscoveredProfile(browser: .cooee, directory: "", name: "cooee", email: nil, installedWebApps: []),
            DiscoveredProfile(cooee: CooeeProfile(name: "work", account: nil)),
        ])
        XCTAssertEqual(config.targets.map(\.name), ["cooee", "cooee · work"])
        XCTAssertEqual(config.targets.map(\.profile), [nil, nil])
    }
}
