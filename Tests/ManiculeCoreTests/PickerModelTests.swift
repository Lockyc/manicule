import XCTest
@testable import ManiculeCore

final class PickerModelTests: XCTestCase {
    private let targets = [
        Target(id: "a", browser: .chrome, profile: "Default", name: "Alpha", email: "a@example.com"),
        Target(id: "b", browser: .chrome, profile: "Profile 1", name: "Beta", email: nil),
        Target(id: "c", browser: .safari, profile: nil, name: "Safari", email: nil),
    ]
    private let unpinned = [
        Target(id: "x", browser: .chrome, profile: "Profile 2", name: "Extra", email: "x@example.com"),
        Target(id: "f", browser: .firefox, profile: nil, name: "Firefox", email: nil),
    ]
    private let link = IncomingLink(url: URL(string: "https://example.com/p?utm_source=x&id=7")!,
                                    sourceApp: nil, receivedAt: Date(timeIntervalSince1970: 0))

    private var strip: [[Target]] { [Array(targets[0...1]), [targets[2]]] }
    private var withMore: [[Target]] { [[unpinned[0]], [unpinned[1]]] }

    private func model(preselected: Target.ID? = nil, more: [[Target]] = []) -> PickerModel {
        PickerModel(link: link, strip: strip, more: more, preselected: preselected)
    }

    /// Two Chrome profiles signed into one domain are often both named after it; the tile then
    /// shows what tells them apart.
    func testTilesSharingAShortNameShowTheirAccountOrFolder() {
        let strip = [
            Target(id: "a", browser: .chrome, profile: "Default", name: "Chrome · example.com", email: "a@example.com"),
            Target(id: "b", browser: .chrome, profile: "Profile 1", name: "Chrome · example.com", email: nil),
            Target(id: "c", browser: .chromium, profile: "Default", name: "Chromium · Home", email: nil),
            Target(id: "d", browser: .safari, profile: nil, name: "Safari", email: nil),
        ]
        XCTAssertEqual(Target.tileDetails(strip), ["a": "a@example.com", "b": "Profile 1"])
        XCTAssertEqual(Target.tileDetails(targets), [:])
    }

    func testDigitsNumberStraightAcrossGroups() {
        var m = model()
        XCTAssertEqual(m.pinned.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(m.handle(.digit(2)), .finish(.open("b", always: false)))
        XCTAssertEqual(m.handle(.digit(3)), .finish(.open("c", always: false)))
    }

    func testDigitBeyondCountIgnored() {
        var m = model()
        XCTAssertNil(m.handle(.digit(4)))
    }

    func testEnterOpensSelection() {
        var m = model(preselected: "c")
        XCTAssertEqual(m.handle(.enter), .finish(.open("c", always: false)))
        var first = model()
        XCTAssertEqual(first.handle(.enter), .finish(.open("a", always: false)), "no preselection selects the first")
    }

    func testOptionEnterOpensAlways() {
        var m = model(preselected: "b")
        XCTAssertEqual(m.handle(.optionEnter), .finish(.open("b", always: true)))
    }

    func testCopyReturnsStrippedURL() {
        var m = model()
        XCTAssertEqual(m.handle(.copy), .finish(.copy(TrackingParameters.stripped(link.url))))
    }

    func testEscapeCancels() {
        var m = model()
        XCTAssertEqual(m.handle(.escape), .finish(.cancel))
    }

    func testArrowsMoveSelectionAndClamp() {
        var m = model()
        XCTAssertNil(m.handle(.left))
        XCTAssertEqual(m.selection, .target("a"), "clamped at the start")
        XCTAssertNil(m.handle(.right))
        XCTAssertEqual(m.selection, .target("b"))
        _ = m.handle(.right)
        _ = m.handle(.right)
        XCTAssertEqual(m.selection, .target("c"), "clamped at the end: More is disabled with nothing under it")
        _ = m.handle(.left)
        XCTAssertEqual(m.selection, .target("b"))
    }

    func testMoreIsDisabledWhenEveryProfileIsPinned() {
        var m = model()
        XCTAssertFalse(m.moreIsEnabled)
        XCTAssertNil(m.handle(.more))
    }

    func testZeroOpensMore() {
        var m = model(more: withMore)
        XCTAssertTrue(m.moreIsEnabled)
        XCTAssertEqual(m.handle(.more), .showMore(highlighted: nil))
        XCTAssertEqual(m.selection, .target("a"), "the menu returns to the strip as it was")
    }

    func testArrowOntoMoreThenEnterOpensMore() {
        var m = model(preselected: "c", more: withMore)
        _ = m.handle(.right)
        XCTAssertEqual(m.selection, .more)
        _ = m.handle(.right)
        XCTAssertEqual(m.selection, .more, "More is the end of the strip")
        XCTAssertEqual(m.handle(.enter), .showMore(highlighted: nil))
        XCTAssertEqual(m.handle(.optionEnter), .showMore(highlighted: nil))
        _ = m.handle(.left)
        XCTAssertEqual(m.selection, .target("c"))
    }

    func testUnpinnedPreselectionSelectsMoreAndHighlightsItsItem() {
        var m = model(preselected: "f", more: withMore)
        XCTAssertEqual(m.selection, .more)
        XCTAssertEqual(m.handle(.enter), .showMore(highlighted: "f"))
        XCTAssertEqual(m.handle(.more), .showMore(highlighted: "f"))
    }

    func testUnknownPreselectionFallsBackToFirst() {
        XCTAssertEqual(model(preselected: "zzz").selection, .target("a"))
    }

    func testNothingPinnedSelectsMore() {
        var m = PickerModel(link: link, strip: [], more: withMore, preselected: nil)
        XCTAssertEqual(m.selection, .more)
        XCTAssertEqual(m.handle(.enter), .showMore(highlighted: nil))
    }

    func testEmptyTargetsOnlyCopyOrCancel() {
        var m = PickerModel(link: link, strip: [], more: [], preselected: nil)
        XCTAssertNil(m.selection)
        XCTAssertNil(m.handle(.enter))
        XCTAssertNil(m.handle(.right))
        XCTAssertNil(m.handle(.more))
        XCTAssertEqual(m.handle(.escape), .finish(.cancel))
    }
}

final class TargetShortNameTests: XCTestCase {
    func testShortNameDropsTheBrowserPrefixOfDefaultNames() {
        let config = Config.defaults(from: [
            DiscoveredProfile(browser: .chromium, directory: "Default", name: "Personal", email: nil, installedWebApps: []),
            DiscoveredProfile(browser: .safari, directory: "", name: "Safari", email: nil, installedWebApps: []),
        ])
        XCTAssertEqual(config.targets.map(\.shortName), ["Personal", "Safari"])
    }

    func testShortNameKeepsAUserNameWhole() {
        XCTAssertEqual(Target(id: "x", browser: .chrome, profile: nil, name: "Work", email: nil).shortName, "Work")
    }
}
