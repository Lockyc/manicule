import XCTest
@testable import ManiculeCore

final class VeljaImportTests: XCTestCase {
    private let firefox = Target(id: "firefox|ff.default", browser: .firefox, profile: "ff.default", name: "Firefox", email: nil)
    private let work = Target(id: "chrome|Profile 2", browser: .chrome, profile: "Profile 2", name: "Chrome · Work", email: nil)
    private let home = Target(id: "chrome|Default", browser: .chrome, profile: "Default", name: "Chrome · Home", email: nil)
    private var targets: [Target] { [firefox, work, home] }

    private func plist(_ rules: [String]) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: ["rules": rules], format: .binary, options: 0)
    }
    private func json(matchers: String = #"[{"kind":"hostSuffix","pattern":"example.com"}]"#, target: String = #""openTarget":"browser:org.mozilla.firefox""#,
                      enabled: Bool = true, sources: String = "[]") -> String {
        #"{"title":"t","isEnabled":\#(enabled),"matchers":\#(matchers),\#(target),"sourceApps":\#(sources)}"#
    }

    func testMapsHostSuffixToTheOnlyFirefoxTarget() {
        let r = VeljaImport.rules(fromPreferences: plist([json()]), targets: targets)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].matchers, [.hostSuffix("example.com")])
        XCTAssertEqual(r[0].target, firefox.id)
        XCTAssertNil(r[0].sourceApp)
    }

    func testMapsMatcherKindsAndSkipsUnknownMatchers() {
        let m = #"[{"kind":"hostExact","pattern":"a.com"},{"kind":"host","pattern":"b.com"},{"kind":"urlContains","pattern":"x"},{"kind":"weird","pattern":"y"}]"#
        let r = VeljaImport.rules(fromPreferences: plist([json(matchers: m)]), targets: targets)
        XCTAssertEqual(r[0].matchers, [.hostExact("a.com"), .hostExact("b.com"), .urlContains("x")])
    }

    func testRuleWithOnlyUnknownMatchersIsSkipped() {
        let m = #"[{"kind":"weird","pattern":"y"}]"#
        XCTAssertTrue(VeljaImport.rules(fromPreferences: plist([json(matchers: m)]), targets: targets).isEmpty)
    }

    func testChromeProfileTargetsAndLegacyBrowserKey() {
        let a = VeljaImport.rules(fromPreferences: plist([json(target: #""openTarget":"browser:com.google.Chrome|Profile 2""#)]), targets: targets)
        XCTAssertEqual(a.map(\.target), [work.id])
        let b = VeljaImport.rules(fromPreferences: plist([json(target: #""browser":"com.google.Chrome|Default""#)]), targets: targets)
        XCTAssertEqual(b.map(\.target), [home.id])
    }

    func testAmbiguousOrMissingTargetsAreSkipped() {
        let chromeNoProfile = json(target: #""openTarget":"browser:com.google.Chrome""#)
        let unknownProfile = json(target: #""openTarget":"browser:com.google.Chrome|Profile 9""#)
        let notInstalled = json(target: #""openTarget":"browser:com.apple.Safari""#)
        XCTAssertTrue(VeljaImport.rules(fromPreferences: plist([chromeNoProfile, unknownProfile, notInstalled]), targets: targets).isEmpty)
    }

    func testDisabledAreSkippedAndSourceAppsHandled() {
        let rules = [json(enabled: false), json(sources: #"["com.apple.mail"]"#), json(sources: #"["a","b"]"#)]
        let r = VeljaImport.rules(fromPreferences: plist(rules), targets: targets)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].sourceApp, "com.apple.mail")
    }

    func testResultCountsSkippedAndDropsDuplicatesOfExistingRules() {
        let existing = Rule(title: "x", matchers: [.hostSuffix("example.com")], target: firefox.id)
        let res = VeljaImport.result(fromPreferences: plist([json(), json(matchers: #"[{"kind":"weird","pattern":"y"}]"#),
                                                            json(matchers: #"[{"kind":"hostExact","pattern":"n.com"}]"#)]),
                                     targets: targets, existing: [existing])
        XCTAssertEqual(res.rules.map(\.matchers), [[.hostExact("n.com")]])
        XCTAssertEqual(res.skipped, 1)
    }

    func testGarbageYieldsNothing() {
        XCTAssertTrue(VeljaImport.rules(fromPreferences: Data("nope".utf8), targets: targets).isEmpty)
    }
}
