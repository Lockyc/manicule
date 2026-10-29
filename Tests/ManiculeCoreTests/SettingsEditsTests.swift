import XCTest
@testable import ManiculeCore

/// The edits Settings makes to a config, window-free.
final class SettingsEditsTests: XCTestCase {
    private func config() -> Config {
        let targets = ["a", "b", "c", "d"].map { Target(id: $0, browser: .chrome, profile: $0, name: $0, email: nil) }
        return Config(targets: targets, visible: ["a", "c"])
    }

    func testShowingATargetKeepsVisibleInTargetOrder() {
        var c = config()
        c.setVisible("b", true)
        XCTAssertEqual(c.visible, ["a", "b", "c"])
        c.setVisible("b", true)
        XCTAssertEqual(c.visible, ["a", "b", "c"], "showing twice adds once")
    }

    func testHidingATarget() {
        var c = config()
        c.setVisible("a", false)
        XCTAssertEqual(c.visible, ["c"])
        XCTAssertEqual(c.targets.count, 4, "hiding never removes the target")
    }

    func testMovingTargetsReordersVisibleToo() {
        var c = config()
        c.moveTargets(fromOffsets: [2], toOffset: 0)
        XCTAssertEqual(c.targets.map(\.id), ["c", "a", "b", "d"])
        XCTAssertEqual(c.visible, ["c", "a"])
        c.moveTargets(fromOffsets: [0, 1], toOffset: 4)
        XCTAssertEqual(c.targets.map(\.id), ["b", "d", "c", "a"])
        XCTAssertEqual(c.visible, ["c", "a"])
    }

    func testMatcherKindAndValueRoundTrip() {
        for kind in Matcher.Kind.allCases {
            let m = Matcher(kind: kind, value: "x")
            XCTAssertEqual(m.kind, kind)
            XCTAssertEqual(m.value, "x")
        }
        XCTAssertEqual(Matcher(kind: .hostSuffix, value: "example.test"), .hostSuffix("example.test"))
        XCTAssertEqual(Set(Matcher.Kind.allCases.map(\.title)).count, Matcher.Kind.allCases.count)
    }
}
