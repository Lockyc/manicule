import XCTest
@testable import ManiculeCore

final class ConfigStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("manicule-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        for path in [dir.path, dir.appendingPathComponent("config.json").path] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        }
        try? FileManager.default.removeItem(at: dir)
    }

    private func writeConfigFile(_ text: String) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("config.json")
        try Data(text.utf8).write(to: file)
        return file
    }

    func testUnreadableFileIsNeverOverwritten() throws {
        let file = try writeConfigFile(#"{"targets":[]}"#)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        let store = ConfigStore(directory: dir)
        XCTAssertEqual(store.load(discovered: discovered), Config.defaults(from: discovered))
        XCTAssertNotNil(store.saveRefusal)
        XCTAssertThrowsError(try store.save(Config.defaults(from: discovered)))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), #"{"targets":[]}"#)
    }

    func testCorruptFileThatCantBeMovedAsideIsNeverOverwritten() throws {
        let file = try writeConfigFile("{not json")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        let store = ConfigStore(directory: dir)
        XCTAssertEqual(store.load(discovered: discovered), Config.defaults(from: discovered))
        XCTAssertNotNil(store.saveRefusal)
        XCTAssertThrowsError(try store.save(Config.defaults(from: discovered)))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "{not json")
    }

    func testCleanLoadsAllowSaving() throws {
        let missing = ConfigStore(directory: dir)
        _ = missing.load(discovered: discovered)
        XCTAssertNil(missing.saveRefusal)
        XCTAssertNoThrow(try missing.save(Config.defaults(from: discovered)))

        _ = try writeConfigFile("{not json")
        let corrupt = ConfigStore(directory: dir)
        _ = corrupt.load(discovered: discovered)
        XCTAssertNil(corrupt.saveRefusal, "moved aside, so nothing is lost by saving")
        XCTAssertNoThrow(try corrupt.save(Config.defaults(from: discovered)))
    }

    func testSaveBeforeLoadIsRefused() {
        XCTAssertThrowsError(try ConfigStore(directory: dir).save(Config.defaults(from: discovered)))
    }

    private let discovered: [DiscoveredProfile] = [
        DiscoveredProfile(browser: .chrome, directory: "Default", name: "Work", email: "a@example.test", installedWebApps: []),
        DiscoveredProfile(browser: .chrome, directory: "Profile 1", name: "Home", email: nil, installedWebApps: []),
        DiscoveredProfile(browser: .firefox, directory: "Profiles/x.default-release", name: "default-release", email: nil, installedWebApps: []),
        DiscoveredProfile(browser: .safari, directory: "", name: "Safari", email: nil, installedWebApps: []),
    ]

    private let doc = "1DocAbCdEfGhIjKlMnOpQrStUvWxYz0123456789"

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
        c.recordPick(link("https://Docs.Google.com/document/d/\(doc)/edit"), target: "chrome|Default", always: false)
        XCTAssertEqual(c.lastChoiceByHost["docs.google.com"], "chrome|Default")
        XCTAssertEqual(c.rememberedDocuments[doc], "chrome|Default")
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

    func testMergeAddsNewProfilesHidden() {
        var c = Config.defaults(from: [discovered[3]])
        c.merge(discovered: discovered)
        XCTAssertEqual(c.targets.map(\.id), ["safari|", "chrome|Default", "chrome|Profile 1", "firefox|Profiles/x.default-release"])
        XCTAssertEqual(c.targets[1].name, "Chrome · Work")
        XCTAssertEqual(c.targets[1].email, "a@example.test")
        XCTAssertEqual(c.visible, ["safari|"])
    }

    func testMergeRefreshesEmailKeepsNameAndOrder() {
        var c = Config.defaults(from: discovered)
        c.targets.reverse()
        c.targets[3].name = "Renamed by me"
        c.targets[3].email = "old@example.test"
        c.visible = ["chrome|Default"]
        var renamed = discovered
        renamed[0].name = "Renamed in Chrome"
        renamed[0].email = "new@example.test"
        let before = c
        c.merge(discovered: renamed)
        XCTAssertEqual(c.targets.map(\.id), before.targets.map(\.id))
        XCTAssertEqual(c.targets.map(\.name), before.targets.map(\.name))
        XCTAssertEqual(c.targets[3].email, "new@example.test")
        XCTAssertEqual(c.visible, ["chrome|Default"])
    }

    func testMergeNeverRemovesTargets() {
        var c = Config.defaults(from: discovered)
        let before = c
        c.merge(discovered: [discovered[3]])
        XCTAssertEqual(c, before)
    }

    func testAvailableTargetsAreDiscoveredOrInAnUnreadableBrowser() {
        var c = Config.defaults(from: discovered)
        c.targets.append(Target(id: "chrome|Profile 9", browser: .chrome, profile: "Profile 9", name: "Gone", email: nil))
        c.targets.append(Target(id: "chromium|Default", browser: .chromium, profile: "Default", name: "Gone too", email: nil))
        let onlySafari = [discovered[3]]
        XCTAssertEqual(c.available(discovered: discovered, unreadable: []),
                       ["chrome|Default", "chrome|Profile 1", "firefox|Profiles/x.default-release", "safari|"])
        XCTAssertEqual(c.available(discovered: onlySafari, unreadable: [.chrome]),
                       ["chrome|Default", "chrome|Profile 1", "chrome|Profile 9", "safari|"],
                       "a browser that can't be read yet isn't penalised")
        XCTAssertEqual(c.routerState(available: ["safari|"]).available, ["safari|"])
    }

    func testRoundTrip() throws {
        var c = Config.defaults(from: discovered)
        c.recordPick(link("https://docs.google.com/document/d/\(doc)/edit"), target: "chrome|Default", always: true)
        c.recordOutcome(link("https://example.test/"), target: "safari|")
        let store = ConfigStore(directory: dir)
        _ = store.load(discovered: discovered)
        try store.save(c)
        XCTAssertEqual(ConfigStore(directory: dir).load(discovered: discovered), c)
    }

    /// A config written by another version: keys missing (defaults fill them) and keys unknown (ignored).
    func testConfigWithMissingAndUnknownKeysDecodes() throws {
        let rule = "6F1C2A4E-0B8D-4C59-9E43-2D1B7A5F0C11"
        let json = """
        {"targets":[{"id":"chrome|Default","browser":"chrome","profile":"Default","name":"Chrome · Work","colour":"red"},
                    {"id":"safari|","browser":"safari"}],
         "visible":["chrome|Default"],
         "rules":[{"id":"\(rule)","title":"r","matchers":[{"hostSuffix":{"_0":"example.test"}}],"target":"safari|"}],
         "lastChoiceByHost":{"example.test":"safari|"},
         "somethingNew":42}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let c = try decoder.decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(c.targets, [
            Target(id: "chrome|Default", browser: .chrome, profile: "Default", name: "Chrome · Work", email: nil),
            Target(id: "safari|", browser: .safari, profile: nil, name: "Safari", email: nil),
        ])
        XCTAssertEqual(c.visible, ["chrome|Default"])
        XCTAssertEqual(c.rules, [Rule(id: UUID(uuidString: rule)!, title: "r", matchers: [.hostSuffix("example.test")],
                                      sourceApp: nil, target: "safari|", isEnabled: true)])
        XCTAssertEqual(c.rememberedDocuments, [:])
        XCTAssertEqual(c.lastChoiceByHost, ["example.test": "safari|"])
        XCTAssertEqual(c.history, [])
    }

    func testHistoryEntryWithoutSourceOrTargetDecodes() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let e = try decoder.decode(HistoryEntry.self, from: Data(#"{"url":"https://example.test/","at":"2026-01-01T00:00:00Z"}"#.utf8))
        XCTAssertEqual(e, HistoryEntry(url: URL(string: "https://example.test/")!, sourceApp: nil, target: nil,
                                       at: Date(timeIntervalSince1970: 1_767_225_600)))
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
