import XCTest
@testable import ManiculeCore

final class FlotillaTests: XCTestCase {
    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("manicule-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        return home
    }

    private func write(_ json: String, home: URL) throws {
        let file = Flotilla.manifest(home: home)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json.write(to: file, atomically: true, encoding: .utf8)
    }

    private let manifest = """
    {"version":1,"windows":[
      {"title":"Rotary Club","colour":"#17458f","groups":["Rotary (interim)","Bulletins"]},
      {"title":"Work|Home","colour":null,"groups":[]}]}
    """

    private let windows = [
        FlotillaWindow(title: "Rotary Club", colour: "#17458f", groups: ["Rotary (interim)", "Bulletins"]),
        FlotillaWindow(title: "Work|Home", colour: nil, groups: []),
    ]

    private func link(_ s: String) -> IncomingLink {
        IncomingLink(url: URL(string: s)!, sourceApp: nil, receivedAt: Date(timeIntervalSince1970: 0))
    }

    func testManifestIsInFlotillasApplicationSupport() {
        XCTAssertEqual(Flotilla.manifest(home: URL(fileURLWithPath: "/Users/x")).path,
                       "/Users/x/Library/Application Support/au.lsjc.flotilla/windows.json")
    }

    func testManifestLoadsWindowsInOrder() throws {
        let home = try makeHome()
        try write(manifest, home: home)
        XCTAssertEqual(Flotilla.load(from: Flotilla.manifest(home: home)), windows)
    }

    func testMissingOrBadManifestIsNothing() throws {
        let home = try makeHome()
        let file = Flotilla.manifest(home: home)
        XCTAssertEqual(Flotilla.load(from: file), [], "missing")
        try write("{not json", home: home)
        XCTAssertEqual(Flotilla.load(from: file), [], "undecodable")
        try write(#"{"version":2,"windows":[{"title":"A","colour":null,"groups":[]}]}"#, home: home)
        XCTAssertEqual(Flotilla.load(from: file), [], "another version")
        try write(#"{"version":1,"windows":[{"colour":null,"groups":[]}]}"#, home: home)
        XCTAssertEqual(Flotilla.load(from: file), [], "a window without a title")
    }

    func testIdsRoundTripTitlesWithPipesAndSpaces() {
        let window = "Work | Home 100%"
        let group = "a|b c/d?"
        XCTAssertEqual(Flotilla.windowID(window), "flotilla|Work%20%7C%20Home%20100%25")
        XCTAssertEqual(Flotilla.groupID(window: window, group: group),
                       "flotilla|Work%20%7C%20Home%20100%25|a%7Cb%20c%2Fd%3F")
        XCTAssert(Flotilla.parse(Flotilla.windowID(window)) == (window, nil))
        XCTAssert(Flotilla.parse(Flotilla.groupID(window: window, group: group)) == (window, group))
        XCTAssert(Flotilla.parse("flotilla|") == (nil, nil))
        XCTAssert(Flotilla.parse("chrome|Default") == (nil, nil))
    }

    func testGroupTargetsCarryTheirWindowsColour() {
        let groups = Flotilla.groupTargets(windows)
        XCTAssertEqual(groups.map(\.id), [Flotilla.groupID(window: "Rotary Club", group: "Rotary (interim)"),
                                          Flotilla.groupID(window: "Rotary Club", group: "Bulletins")])
        XCTAssertEqual(groups.map(\.name), ["flotilla · Rotary Club ▸ Rotary (interim)",
                                            "flotilla · Rotary Club ▸ Bulletins"])
        XCTAssertEqual(groups.map(\.colour), ["#17458f", "#17458f"])
        XCTAssertEqual(groups.map(\.browser), [.flotilla, .flotilla])
    }

    // MARK: - Config and routing

    private let saf = DiscoveredProfile(browser: .safari, directory: "", name: "Safari", email: nil, installedWebApps: [])
    private let plain = DiscoveredProfile(browser: .flotilla, directory: "", name: "flotilla", email: nil, installedWebApps: [])

    private func windowProfiles() -> [DiscoveredProfile] {
        windows.map { DiscoveredProfile(window: $0) }
    }

    func testWindowsAreDiscoveredAsProfiles() {
        var c = Config.defaults(from: [saf, plain])
        c.merge(discovered: [saf, plain] + windowProfiles())
        let rotary = Flotilla.windowID("Rotary Club")
        let work = Flotilla.windowID("Work|Home")
        XCTAssertEqual(c.targets.map(\.id), ["safari|", "flotilla|", rotary, work])
        XCTAssertEqual(c.targets.map(\.name), ["Safari", "flotilla", "flotilla · Rotary Club", "flotilla · Work|Home"])
        XCTAssertEqual(c.targets.map(\.colour), [nil, nil, "#17458f", nil])
        XCTAssertEqual(c.visible, ["safari|", "flotilla|"], "windows found later merge unpinned")
        XCTAssertEqual(c.available(discovered: [saf, plain] + windowProfiles(), unreadable: []),
                       ["safari|", "flotilla|", rotary, work])
        XCTAssertEqual(c.available(discovered: [saf, plain], unreadable: []), ["safari|", "flotilla|"],
                       "a closed window is not found")
    }

    func testWindowColourIsRefreshedOnMerge() {
        var c = Config.defaults(from: [plain] + windowProfiles())
        var recoloured = windows
        recoloured[0].colour = "#ff0000"
        c.targets[1].name = "Club"
        c.merge(discovered: [plain] + recoloured.map { DiscoveredProfile(window: $0) })
        XCTAssertEqual(c.targets[1].colour, "#ff0000")
        XCTAssertEqual(c.targets[1].name, "Club")
    }

    private func pinnedConfig() -> Config {
        var c = Config.defaults(from: [saf, plain] + windowProfiles())
        c.visible = ["safari|", "flotilla|", Flotilla.windowID("Rotary Club")]
        return c
    }

    func testGroupsAreUnderMoreNeverTheStrip() {
        let c = pinnedConfig()
        let groups = Flotilla.groupTargets(windows)
        let state = c.routerState(available: Set(c.targets.map(\.id)), flotillaGroups: groups)
        XCTAssertEqual(state.pickerTargets.map(\.id), ["safari|", "flotilla|", Flotilla.windowID("Rotary Club")])
        XCTAssertEqual(state.overflowGroups.map { $0.map(\.id) },
                       [[Flotilla.windowID("Work|Home")] + groups.map(\.id)])
        XCTAssertFalse(state.visible.contains(groups[0].id))
        XCTAssertTrue(state.available.isSuperset(of: groups.map(\.id)))
        XCTAssertEqual(state.target(groups[1].id), groups[1])
    }

    func testGroupIdsUnavailableWithoutFlotilla() {
        let c = pinnedConfig()
        let groups = Flotilla.groupTargets(windows)
        var config = c
        config.rules = [Rule(title: "r", matchers: [.hostSuffix("example.com")], target: groups[1].id)]
        let withFlotilla = config.routerState(available: Set(c.targets.map(\.id)), flotillaGroups: groups)
        XCTAssertEqual(Router.decide(link("https://example.com/"), state: withFlotilla),
                       .open(groups[1], .rule(config.rules[0].id)))
        let without = config.routerState(available: ["safari|"], flotillaGroups: groups)
        XCTAssertEqual(Router.decide(link("https://example.com/"), state: without), .pick(preselected: "safari|"))
        XCTAssertNil(without.target(groups[1].id))
        XCTAssertFalse(without.targets.contains(groups[1]))
    }

    func testRememberedGoneGroupStillRoutesToFlotilla() {
        let doc = "1DocAbCdEfGhIjKlMnOpQrStUvWxYz0123456789"
        let gone = Flotilla.groupID(window: "Rotary Club", group: "Minutes")
        var c = pinnedConfig()
        c.rememberedDocuments[doc] = gone
        let state = c.routerState(available: Set(c.targets.map(\.id)), flotillaGroups: Flotilla.groupTargets(windows))
        let closed = Target(id: gone, browser: .flotilla, profile: nil,
                            name: "flotilla · Rotary Club ▸ Minutes (closed)", email: nil)
        XCTAssertEqual(Router.decide(link("https://docs.google.com/document/d/\(doc)/edit"), state: state),
                       .open(closed, .rememberedDocument))
        XCTAssertNil(state.target(Flotilla.windowID("Gone")), "a gone window is not synthesized")
    }
}
