import XCTest
@testable import ManiculeCore

final class RouterTests: XCTestCase {
    let def = Target(id: "chrome|Default", browser: .chrome, profile: "Default", name: "Work", email: "w@example.com")
    let p3 = Target(id: "chrome|Profile 3", browser: .chrome, profile: "Profile 3", name: "Home", email: "h@example.com")
    let ff = Target(id: "firefox|", browser: .firefox, profile: nil, name: "Firefox", email: nil)
    let saf = Target(id: "safari|", browser: .safari, profile: nil, name: "Safari", email: nil)
    let doc = "1DocAbCdEfGhIjKlMnOpQrStUvWxYz0123456789"

    func state(rules: [Rule] = [], remembered: [String: String] = [:], last: [String: String] = [:],
               visible: [String]? = nil, available: Set<String>? = nil) -> RouterState {
        let targets = [def, p3, ff, saf]
        return RouterState(targets: targets, visible: visible ?? targets.map(\.id), rules: rules,
                           rememberedDocuments: remembered, lastChoiceByHost: last,
                           available: available ?? Set(targets.map(\.id)))
    }

    func link(_ s: String, app: String? = nil) -> IncomingLink {
        IncomingLink(url: URL(string: s)!, sourceApp: app, receivedAt: Date(timeIntervalSince1970: 0))
    }

    func testEmailRoutesToMatchingChromeProfile() {
        let rule = Rule(title: "g", matchers: [.hostSuffix("google.com")], target: ff.id)
        let d = Router.decide(link("https://docs.google.com/document/d/\(doc)/edit?authuser=h%40example.com"),
                              state: state(rules: [rule]))
        XCTAssertEqual(d, .open(p3, .accountEmail))
    }

    func testEmailForUnknownAccountFallsThrough() {
        let d = Router.decide(link("https://docs.google.com/document/d/\(doc)/edit?authuser=z%40example.com"), state: state())
        XCTAssertEqual(d, .pick(preselected: def.id))
    }

    func testFirstMatchingRuleWins() {
        let r1 = Rule(title: "a", matchers: [.hostSuffix("example.com")], target: ff.id)
        let r2 = Rule(title: "b", matchers: [.hostSuffix("example.com")], target: saf.id)
        XCTAssertEqual(Router.decide(link("https://example.com/"), state: state(rules: [r1, r2])), .open(ff, .rule(r1.id)))
        XCTAssertEqual(Router.decide(link("https://example.com/"), state: state(rules: [r2, r1])), .open(saf, .rule(r2.id)))
    }

    func testRuleBeatsRememberedDocument() {
        let r = Rule(title: "a", matchers: [.hostSuffix("google.com")], target: saf.id)
        let d = Router.decide(link("https://docs.google.com/document/d/\(doc)/edit"),
                              state: state(rules: [r], remembered: [doc: def.id]))
        XCTAssertEqual(d, .open(saf, .rule(r.id)))
    }

    func testRememberedDocumentOpens() {
        let d = Router.decide(link("https://docs.google.com/document/d/\(doc)/edit"),
                              state: state(remembered: [doc: def.id]))
        XCTAssertEqual(d, .open(def, .rememberedDocument))
    }

    func testPickPreselectsLastChoiceForHost() {
        let d = Router.decide(link("https://Example.com/a"), state: state(last: ["example.com": ff.id]))
        XCTAssertEqual(d, .pick(preselected: ff.id))
    }

    func testPickPreselectsFirstVisibleWhenNoHistory() {
        let d = Router.decide(link("https://example.com/a"), state: state(visible: [p3.id, ff.id]))
        XCTAssertEqual(d, .pick(preselected: p3.id))
    }

    func testLastChoiceNotVisibleFallsToFirstVisible() {
        let d = Router.decide(link("https://example.com/a"),
                              state: state(last: ["example.com": saf.id], visible: [p3.id, ff.id]))
        XCTAssertEqual(d, .pick(preselected: p3.id))
    }

    func testDanglingTargetsFallThroughToPicker() {
        let r = Rule(title: "a", matchers: [.hostSuffix("google.com")], target: "chrome|Gone")
        let d = Router.decide(link("https://docs.google.com/document/d/\(doc)/edit"),
                              state: state(rules: [r], remembered: [doc: "chrome|Gone"],
                                           last: ["docs.google.com": "chrome|Gone"]))
        XCTAssertEqual(d, .pick(preselected: def.id))
    }

    /// A target still in the config whose profile (or browser) is gone from this Mac.
    func testTargetNotFoundOnThisMacIsDanglingInEveryStep() {
        let gone: Set<String> = [def.id, ff.id, saf.id]
        let viaEmail = Router.decide(link("https://docs.google.com/document/d/\(doc)/edit?authuser=h%40example.com"),
                                     state: state(available: gone))
        XCTAssertEqual(viaEmail, .pick(preselected: def.id))
        let r = Rule(title: "a", matchers: [.hostSuffix("example.com")], target: p3.id)
        XCTAssertEqual(Router.decide(link("https://example.com/"), state: state(rules: [r], available: gone)),
                       .pick(preselected: def.id))
        XCTAssertEqual(Router.decide(link("https://docs.google.com/document/d/\(doc)/edit"),
                                     state: state(remembered: [doc: p3.id], available: gone)),
                       .pick(preselected: def.id))
        XCTAssertEqual(Router.decide(link("https://example.com/"),
                                     state: state(last: ["example.com": p3.id], visible: [p3.id, ff.id], available: gone)),
                       .pick(preselected: ff.id))
    }

    func testPickerStripLeavesOutTargetsNotFound() {
        let s = state(visible: [p3.id, def.id, saf.id], available: [def.id, ff.id, saf.id])
        XCTAssertEqual(s.pickerTargets, [def, saf])
    }

    func testHostlessURLGoesToPicker() {
        for s in ["file:///tmp/a.html", "http://localhost:55801/?key=k"] {
            let r = Rule(title: "a", matchers: [.hostSuffix("example.com")], target: ff.id)
            let d = Router.decide(link(s), state: state(rules: [r], last: ["": ff.id]))
            XCTAssertEqual(d, .pick(preselected: def.id), s)
        }
    }
}
