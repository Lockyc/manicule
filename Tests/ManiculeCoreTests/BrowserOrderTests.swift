import XCTest
@testable import ManiculeCore

/// Targets ordered and grouped by browser: the browser order first, then each browser's own
/// profile order.
final class BrowserOrderTests: XCTestCase {
    private func t(_ id: String, _ browser: Browser) -> Target {
        Target(id: id, browser: browser, profile: id, name: id, email: nil)
    }

    private func config() -> Config {
        let targets = [t("c1", .chrome), t("f1", .firefox), t("c2", .chrome), t("s", .safari), t("c3", .chrome)]
        return Config(targets: targets, visible: ["c1", "f1", "c3", "s"])
    }

    func testMissingBrowserOrderFollowsFirstAppearanceThenTheRest() throws {
        let json = """
        {"targets":[{"id":"firefox|","browser":"firefox"},{"id":"chrome|Default","browser":"chrome"},
                    {"id":"firefox|b","browser":"firefox"}],
         "visible":["firefox|"]}
        """
        let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(c.browserOrder, [.firefox, .chrome, .chromium, .safari, .flotilla])
        XCTAssertEqual(config().browserOrder, [.chrome, .firefox, .safari, .chromium, .flotilla])
    }

    func testStoredBrowserOrderIsCompletedAndUnknownBrowsersDropped() throws {
        let json = """
        {"targets":[{"id":"chrome|Default","browser":"chrome"}],
         "browserOrder":["safari","netscape","safari"]}
        """
        let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(c.browserOrder, [.safari, .chrome, .chromium, .firefox, .flotilla])
    }

    func testBrowserOrderRoundTrips() throws {
        var c = config()
        c.moveBrowser(.safari, to: .chrome)
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(decoded, c)
        XCTAssertEqual(decoded.browserOrder.first, .safari)
    }

    func testOrderedTargetsGroupByBrowserKeepingProfileOrder() {
        XCTAssertEqual(config().orderedTargets.map(\.id), ["c1", "c2", "c3", "f1", "s"])
    }

    func testMovingABrowserTakesTheDestinationsPlace() {
        var c = config()
        c.moveBrowser(.safari, to: .chrome)
        XCTAssertEqual(c.browserOrder, [.safari, .chrome, .firefox, .chromium, .flotilla])
        XCTAssertEqual(c.orderedTargets.map(\.id), ["s", "c1", "c2", "c3", "f1"])
        c.moveBrowser(.safari, to: .firefox)
        XCTAssertEqual(c.browserOrder, [.chrome, .firefox, .safari, .chromium, .flotilla])
        c.moveBrowser(.chrome, to: .chrome)
        XCTAssertEqual(c.browserOrder, [.chrome, .firefox, .safari, .chromium, .flotilla])
    }

    func testMovingProfilesStaysWithinTheirBrowser() {
        var c = config()
        c.moveProfiles(of: .chrome, fromOffsets: [2], toOffset: 0)
        XCTAssertEqual(c.orderedTargets.map(\.id), ["c3", "c1", "c2", "f1", "s"])
        XCTAssertEqual(c.targets.map(\.id), ["c3", "f1", "c1", "s", "c2"], "other browsers keep their slots")
        c.moveProfiles(of: .chrome, fromOffsets: [0], toOffset: 3)
        XCTAssertEqual(c.orderedTargets.map(\.id), ["c1", "c2", "c3", "f1", "s"])
        c.moveProfiles(of: .chrome, fromOffsets: [7], toOffset: 0)
        XCTAssertEqual(c.orderedTargets.map(\.id), ["c1", "c2", "c3", "f1", "s"], "an offset outside the browser is ignored")
    }

    func testPinningKeepsVisibleInEffectiveOrder() {
        var c = config()
        c.moveBrowser(.safari, to: .chrome)
        c.setVisible("c2", true)
        XCTAssertEqual(c.visible, ["s", "c1", "c2", "c3", "f1"])
    }

    func testStripAndOverflowAreGroupedInEffectiveOrder() {
        var c = config()
        c.moveBrowser(.firefox, to: .chrome)
        let all = Set(c.targets.map(\.id))
        let state = c.routerState(available: all.subtracting(["c3"]))
        XCTAssertEqual(state.pickerTargets.map(\.id), ["f1", "c1", "s"])
        XCTAssertEqual(state.pickerGroups.map { $0.map(\.id) }, [["f1"], ["c1"], ["s"]])
        XCTAssertEqual(state.overflowGroups.map { $0.map(\.id) }, [["c2"]], "unavailable targets are in neither")
        c.setVisible("c2", true)
        XCTAssertEqual(c.routerState(available: all).overflowGroups, [])
        XCTAssertEqual(c.routerState(available: all).pickerGroups.map { $0.map(\.id) }, [["f1"], ["c1", "c2", "c3"], ["s"]])
    }

    func testSettingsSectionsAreBrowsersInstalledOrWithTargets() {
        var c = config()
        c.moveBrowser(.chromium, to: .chrome)
        XCTAssertEqual(c.browserSections(including: []), [.chrome, .firefox, .safari])
        XCTAssertEqual(c.browserSections(including: [.chromium]), [.chromium, .chrome, .firefox, .safari])
        XCTAssertEqual(c.targets(of: .chrome).map(\.id), ["c1", "c2", "c3"])
    }
}
