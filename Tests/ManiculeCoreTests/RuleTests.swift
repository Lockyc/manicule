import XCTest
@testable import ManiculeCore

final class RuleTests: XCTestCase {
    private func rule(_ matchers: [Matcher], sourceApp: String? = nil, enabled: Bool = true) -> Rule {
        Rule(id: UUID(), title: "t", matchers: matchers, sourceApp: sourceApp,
             target: "chrome|Profile 1", isEnabled: enabled)
    }
    private func url(_ s: String) -> URL { URL(string: s)! }

    func testHostSuffixMatchesSubdomainsNotLookalikes() {
        let m = Matcher.hostSuffix("example.test")
        XCTAssertTrue(m.matches(url("https://www.example.test/a")))
        XCTAssertTrue(m.matches(url("https://EXAMPLE.test/a")))
        XCTAssertFalse(m.matches(url("https://notexample.test/a")))
    }

    func testRuleWithoutConditionsNeverMatches() {
        XCTAssertFalse(rule([]).matches(url: url("https://example.test/"), sourceApp: nil))
        XCTAssertFalse(rule([], sourceApp: "com.example.Mail").matches(url: url("https://example.test/"),
                                                                      sourceApp: "com.example.Mail"))
    }

    func testAllMatchersMustHold() {
        let r = rule([.hostExact("docs.example.test"), .pathContains("/u/1/")])
        XCTAssertTrue(r.matches(url: url("https://docs.example.test/u/1/document/d/X"), sourceApp: nil))
        XCTAssertFalse(r.matches(url: url("https://docs.example.test/u/0/document/d/X"), sourceApp: nil))
    }

    func testRegexAndQueryContains() {
        XCTAssertTrue(Matcher.regex("^https://[a-z]+\\.example\\.test/x").matches(url("https://abc.example.test/x/y")))
        XCTAssertFalse(Matcher.regex("^https://[a-z]+\\.example\\.test/x").matches(url("https://abc.example.test/z")))
        XCTAssertTrue(Matcher.queryContains("tab=2").matches(url("https://example.test/?a=1&tab=2")))
        XCTAssertFalse(Matcher.queryContains("tab=2").matches(url("https://example.test/?tab=3")))
        XCTAssertTrue(Matcher.urlContains("example.test/x").matches(url("https://example.test/x")))
    }

    func testInvalidRegexNeverMatches() {
        XCTAssertFalse(Matcher.regex("(").matches(url("https://example.test/")))
    }

    func testSourceAppRestriction() {
        let r = rule([.hostSuffix("example.test")], sourceApp: "com.example.Mail")
        let u = url("https://example.test/")
        XCTAssertTrue(r.matches(url: u, sourceApp: "com.example.Mail"))
        XCTAssertFalse(r.matches(url: u, sourceApp: "com.example.Other"))
        XCTAssertFalse(r.matches(url: u, sourceApp: nil))
    }

    func testDisabledRuleNeverMatches() {
        let r = rule([.hostSuffix("example.test")], enabled: false)
        XCTAssertFalse(r.matches(url: url("https://example.test/"), sourceApp: nil))
    }

    func testAlwaysStripsWWW() {
        let r = Rule.always(host: "www.example.test", target: "chrome|Profile 26")
        XCTAssertEqual(r.matchers, [.hostSuffix("example.test")])
        XCTAssertEqual(r.title, "www.example.test → chrome|Profile 26")
        XCTAssertEqual(r.target, "chrome|Profile 26")
    }

    func testEmptyHostNeverMatchesHostMatchers() {
        let u = url("file:///tmp/a.html")
        XCTAssertFalse(Matcher.hostSuffix("").matches(u))
        XCTAssertFalse(Matcher.hostExact("").matches(u))
    }

    func testCodableRoundTripAllMatcherKinds() throws {
        let r = rule([.hostExact("a.test"), .hostSuffix("b.test"), .pathContains("/p"),
                      .queryContains("q=1"), .urlContains("c"), .regex("^https")],
                     sourceApp: "com.example.Mail")
        let back = try JSONDecoder().decode(Rule.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r)
    }
}
