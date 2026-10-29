import XCTest
@testable import ManiculeCore

final class ConfigStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("manicule-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private let discovered: [DiscoveredProfile] = [
        DiscoveredProfile(browser: .chrome, directory: "Default", name: "Work", email: "a@example.test", installedWebApps: []),
        DiscoveredProfile(browser: .chrome, directory: "Profile 1", name: "Home", email: nil, installedWebApps: []),
        DiscoveredProfile(browser: .firefox, directory: "Profiles/x.default-release", name: "default-release", email: nil, installedWebApps: []),
        DiscoveredProfile(browser: .safari, directory: "", name: "Safari", email: nil, installedWebApps: []),
    ]

    private func link(_ s: String) -> IncomingLink {
        IncomingLink(url: URL(string: s)!, sourceApp: nil, receivedAt: Date(timeIntervalSince1970: 0))
    }

    func testDefaultsTargetEveryDiscoveredProfileAllVisible() {
        let c = Config.defaults(from: discovered)
        XCTAssertEqual(c.targets.map(\.id), ["chrome|Default", "chrome|Profile 1", "firefox|Profiles/x.default-release", "safari|"])
        XCTAssertEqual(c.targets.map(\.name), ["Chrome · Work", "Chrome · Home", "Firefox", "Safari"])
        XCTAssertEqual(c.targets[0].email, "a@example.test")
        XCTAssertEqual(c.visible, c.targets.map(\.id))
        XCTAssertTrue(c.rules.isEmpty && c.history.isEmpty)
    }

    func testSeveralFirefoxProfilesAreNamed() {
        let two = [
            DiscoveredProfile(browser: .firefox, directory: "a", name: "one", email: nil, installedWebApps: []),
            DiscoveredProfile(browser: .firefox, directory: "b", name: "two", email: nil, installedWebApps: []),
        ]
        XCTAssertEqual(Config.defaults(from: two).targets.map(\.name), ["Firefox · one", "Firefox · two"])
    }

    func testRecordPickSetsLastChoiceAndRemembersDocument() {
        var c = Config.defaults(from: discovered)
        c.recordPick(link("https://Docs.Google.com/document/d/abc123/edit"), target: "chrome|Default", always: false)
        XCTAssertEqual(c.lastChoiceByHost["docs.google.com"], "chrome|Default")
        XCTAssertEqual(c.rememberedDocuments["abc123"], "chrome|Default")
        XCTAssertTrue(c.rules.isEmpty)
    }

    func testRecordPickAlwaysAppendsHostRule() {
        var c = Config.defaults(from: discovered)
        c.recordPick(link("https://example.test/x"), target: "safari|", always: true)
        XCTAssertEqual(c.rules.count, 1)
        XCTAssertEqual(c.rules[0].matchers, [.hostSuffix("example.test")])
        XCTAssertEqual(c.rules[0].target, "safari|")
    }

    func testRecordPickOnNonGoogleURLRemembersNoDocument() {
        var c = Config.defaults(from: discovered)
        c.recordPick(link("https://example.test/d/abc"), target: "safari|", always: false)
        XCTAssertTrue(c.rememberedDocuments.isEmpty)
    }

    func testHostlessURLSetsNoLastChoiceNorRule() {
        var c = Config.defaults(from: discovered)
        c.recordPick(link("file:///tmp/a.html"), target: "safari|", always: true)
        XCTAssertTrue(c.lastChoiceByHost.isEmpty)
        XCTAssertTrue(c.rules.isEmpty)
    }

    func testHistoryCappedAt100() {
        var c = Config.defaults(from: discovered)
        for i in 0..<105 { c.recordOutcome(link("https://example.test/\(i)"), target: nil) }
        XCTAssertEqual(c.history.count, 100)
        XCTAssertEqual(c.history.first?.url.absoluteString, "https://example.test/5")
        XCTAssertEqual(c.history.last?.url.absoluteString, "https://example.test/104")
    }

    func testRoundTrip() throws {
        var c = Config.defaults(from: discovered)
        c.recordPick(link("https://docs.google.com/document/d/abc/edit"), target: "chrome|Default", always: true)
        c.recordOutcome(link("https://example.test/"), target: "safari|")
        let store = ConfigStore(directory: dir)
        try store.save(c)
        XCTAssertEqual(store.load(discovered: discovered), c)
    }

    func testMissingFileGivesDefaults() {
        XCTAssertEqual(ConfigStore(directory: dir).load(discovered: discovered), Config.defaults(from: discovered))
    }

    func testCorruptFileMovedAsideNotOverwritten() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: dir.appendingPathComponent("config.json"))
        let c = ConfigStore(directory: dir).load(discovered: discovered)
        XCTAssertEqual(c, Config.defaults(from: discovered))
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let aside = try XCTUnwrap(names.first { $0.hasPrefix("config.corrupt-") && $0.hasSuffix(".json") })
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent(aside), encoding: .utf8), "{not json")
    }
}
