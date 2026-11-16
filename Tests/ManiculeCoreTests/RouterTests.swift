import XCTest
@testable import ManiculeCore

final class RouterTests: XCTestCase {
    let def = Target(id: "chrome|Default", browser: .chrome, profile: "Default", name: "Work", email: "w@example.com")
    let p3 = Target(id: "chrome|Profile 3", browser: .chrome, profile: "Profile 3", name: "Home", email: "h@example.com")
    let ff = Target(id: "firefox|", browser: .firefox, profile: nil, name: "Firefox", email: nil)
    let saf = Target(id: "safari|", browser: .safari, profile: nil, name: "Safari", email: nil)
    let doc = "1DocAbCdEfGhIjKlMnOpQrStUvWxYz0123456789"

    func state(rules: [Rule] = [], lastDoc: [String: String] = [:], last: [String: String] = [:],
               visible: [String]? = nil, available: Set<String>? = nil) -> RouterState {
        let targets = [def, p3, ff, saf]
        return RouterState(targets: targets, visible: visible ?? targets.map(\.id), rules: rules,
                           lastChoiceByDocument: lastDoc, lastChoiceByHost: last,
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

    func testRuleBeatsLastChoiceForDocument() {
        let r = Rule(title: "a", matchers: [.hostSuffix("google.com")], target: saf.id)
        let d = Router.decide(link("https://docs.google.com/document/d/\(doc)/edit"),
                              state: state(rules: [r], lastDoc: [doc: def.id]))
        XCTAssertEqual(d, .open(saf, .rule(r.id)))
    }

    /// A document's last choice never opens it unseen; it outranks the host's last choice.
    func testLastChoiceForDocumentIsPreselected() {
        let d = Router.decide(link("https://docs.google.com/document/d/\(doc)/edit"),
                              state: state(lastDoc: [doc: ff.id], last: ["docs.google.com": saf.id]))
        XCTAssertEqual(d, .pick(preselected: ff.id))
    }

    func testPickPreselectsLastChoiceForHost() {
        let d = Router.decide(link("https://Example.com/a"), state: state(last: ["example.com": ff.id]))
        XCTAssertEqual(d, .pick(preselected: ff.id))
    }

    func testPickPreselectsFirstVisibleWhenNoHistory() {
        let d = Router.decide(link("https://example.com/a"), state: state(visible: [p3.id, ff.id]))
        XCTAssertEqual(d, .pick(preselected: p3.id))
    }

    /// An unpinned target is still in the picker, under ⋯, so a last choice there is preselected.
    func testLastChoiceNotPinnedIsStillPreselected() {
        let d = Router.decide(link("https://example.com/a"),
                              state: state(last: ["example.com": saf.id], visible: [p3.id, ff.id]))
        XCTAssertEqual(d, .pick(preselected: saf.id))
    }

    func testNothingPinnedPreselectsNothing() {
        XCTAssertEqual(Router.decide(link("https://example.com/a"), state: state(visible: [])), .pick(preselected: nil))
    }

    func testDanglingTargetsFallThroughToPicker() {
        let r = Rule(title: "a", matchers: [.hostSuffix("google.com")], target: "chrome|Gone")
        let d = Router.decide(link("https://docs.google.com/document/d/\(doc)/edit"),
                              state: state(rules: [r], lastDoc: [doc: "chrome|Gone"],
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
                                     state: state(lastDoc: [doc: p3.id], available: gone)),
                       .pick(preselected: def.id))
        XCTAssertEqual(Router.decide(link("https://example.com/"),
                                     state: state(last: ["example.com": p3.id], visible: [p3.id, ff.id], available: gone)),
                       .pick(preselected: ff.id))
    }

    func testPickerStripLeavesOutTargetsNotFound() {
        let s = state(visible: [p3.id, def.id, saf.id], available: [def.id, ff.id, saf.id])
        XCTAssertEqual(s.pickerTargets, [def, saf])
    }

    func testHandledSchemesAreWebAndFile() {
        for s in ["http://example.com", "HTTPS://example.com", "file:///tmp/a.html"] {
            XCTAssertTrue(IncomingLink.isHandled(URL(string: s)!), s)
        }
        for s in ["mailto:a@example.com", "ftp://example.com/x", "x-manicule:y"] {
            XCTAssertFalse(IncomingLink.isHandled(URL(string: s)!), s)
        }
    }

    // MARK: Meet and cooee

    let chromeWork = Target(id: "chrome|Default", browser: .chrome, profile: "Default", name: "Chrome · Work", email: "me@work.example")
    let chromeHome = Target(id: "chrome|Profile 1", browser: .chrome, profile: "Profile 1", name: "Chrome · Home", email: "me@home.example")
    let safari = Target(id: "safari|", browser: .safari, profile: nil, name: "Safari", email: nil)
    let cooeePlain = Target(id: Cooee.plainID, browser: .cooee, profile: nil, name: "cooee", email: nil)
    let cooeeWork = Target(id: Cooee.profileID("work"), browser: .cooee, profile: nil, name: "cooee · work", email: "me@work.example")
    let cooeeHome = Target(id: Cooee.profileID("home"), browser: .cooee, profile: nil, name: "cooee · home", email: "me@home.example")
    let meetLink = IncomingLink(url: URL(string: "https://meet.google.com/abc-defg-hij")!, sourceApp: nil,
                                receivedAt: Date(timeIntervalSince1970: 0))
    let meetWork = "https://meet.google.com/abc-defg-hij?authuser=me%40work.example"
    let docsWork = "https://docs.google.com/document/d/1DocAbCdEfGhIjKlMnOpQrStUvWxYz0123456789/edit?authuser=me%40work.example"

    func meetState(_ targets: [Target]? = nil, rules: [Rule] = [], last: [String: String] = [:]) -> RouterState {
        let targets = targets ?? [chromeWork, chromeHome, safari, cooeePlain, cooeeWork, cooeeHome]
        return RouterState(targets: targets, visible: [chromeWork.id, safari.id], rules: rules,
                           lastChoiceByDocument: [:], lastChoiceByHost: last,
                           available: Set(targets.map(\.id)))
    }

    func testMeetEmailOpensMatchingCooeeProfile() {
        XCTAssertEqual(Router.decide(link(meetWork), state: meetState()), .open(cooeeWork, .accountEmail))
    }

    /// A Chrome profile in the same account is not a Meet target while cooee is available.
    func testMeetEmailMatchingOnlyChromeAsks() {
        let s = meetState([chromeWork, chromeHome, safari, cooeePlain, cooeeHome])
        XCTAssertEqual(Router.decide(link(meetWork), state: s), .pick(preselected: cooeeHome.id))
    }

    func testMeetWithoutEmailAsks() {
        XCTAssertEqual(Router.decide(meetLink, state: meetState()), .pick(preselected: cooeeWork.id))
    }

    func testMeetPreselectsFirstCooeeAccount() {
        XCTAssertEqual(Router.decide(meetLink, state: meetState()), .pick(preselected: cooeeWork.id))
        let plainOnly = meetState([chromeWork, chromeHome, safari, cooeePlain])
        XCTAssertEqual(Router.decide(meetLink, state: plainOnly), .pick(preselected: cooeePlain.id))
    }

    /// A last choice under ⋯ in the Meet layout still wins over the first cooee account.
    func testMeetKeepsLastChoiceForHost() {
        let s = meetState(last: ["meet.google.com": chromeHome.id])
        XCTAssertEqual(Router.decide(meetLink, state: s), .pick(preselected: chromeHome.id))
    }

    func testNonMeetNeverPreselectsCooee() {
        var s = meetState([cooeeWork, cooeePlain, cooeeHome, chromeWork, chromeHome, safari],
                          last: ["example.com": cooeeWork.id])
        s.visible.insert(cooeeHome.id, at: 0)
        XCTAssertEqual(Router.decide(link("https://example.com/"), state: s), .pick(preselected: chromeWork.id))
    }

    func testMeetRuleStillWins() {
        let r = Rule(title: "m", matchers: [.hostSuffix("meet.google.com")], target: chromeHome.id)
        XCTAssertEqual(Router.decide(meetLink, state: meetState(rules: [r])), .open(chromeHome, .rule(r.id)))
    }

    func testNonMeetEmailIgnoresCooee() {
        let s = meetState([cooeePlain, cooeeWork, cooeeHome, chromeWork, chromeHome, safari])
        XCTAssertEqual(Router.decide(link(docsWork), state: s), .open(chromeWork, .accountEmail))
    }

    func testCooeeRuleIgnoredForNonMeet() {
        let r = Rule(title: "e", matchers: [.hostSuffix("example.com")], target: cooeeWork.id)
        XCTAssertEqual(Router.decide(link("https://example.com/"), state: meetState(rules: [r])),
                       .pick(preselected: chromeWork.id))
    }

    func testMeetWithoutCooeeRoutesAsBefore() {
        let s = meetState([chromeWork, chromeHome, safari])
        XCTAssertEqual(Router.decide(link(meetWork), state: s), .open(chromeWork, .accountEmail))
        let layout = Router.pickerLayout(meetLink, state: s)
        XCTAssertEqual(layout.strip, s.pickerGroups)
        XCTAssertEqual(layout.more, s.overflowGroups)
    }

    func testMeetPickerStripIsCooeeAccounts() {
        let layout = Router.pickerLayout(meetLink, state: meetState())
        XCTAssertEqual(layout.strip.flatMap { $0 }.map(\.id), [Cooee.profileID("work"), Cooee.profileID("home")])
        XCTAssertEqual(Set(layout.more.flatMap { $0 }.map(\.id)),
                       Set([chromeWork, chromeHome, safari, cooeePlain].map(\.id)))
        XCTAssertEqual(layout.more.map { $0.first?.browser }, [.chrome, .safari, .cooee])
    }

    func testMeetPickerFallsBackToPlainCooee() {
        let layout = Router.pickerLayout(meetLink, state: meetState([chromeWork, chromeHome, safari, cooeePlain]))
        XCTAssertEqual(layout.strip, [[cooeePlain]])
        XCTAssertEqual(layout.more, [[chromeWork, chromeHome], [safari]])
    }

    func testNonMeetPickerHasNoCooee() {
        var s = meetState()
        s.visible.append(cooeeWork.id)
        let layout = Router.pickerLayout(link(docsWork), state: s)
        func drop(_ groups: [[Target]]) -> [[Target]] {
            groups.map { $0.filter { $0.browser != .cooee } }.filter { !$0.isEmpty }
        }
        XCTAssertEqual(layout.strip, drop(s.pickerGroups))
        XCTAssertEqual(layout.more, drop(s.overflowGroups))
        XCTAssertFalse((layout.strip + layout.more).joined().contains { $0.browser == .cooee })
    }

    func testHostlessURLGoesToPicker() {
        for s in ["file:///tmp/a.html", "http://localhost:55801/?key=k"] {
            let r = Rule(title: "a", matchers: [.hostSuffix("example.com")], target: ff.id)
            let d = Router.decide(link(s), state: state(rules: [r], last: ["": ff.id]))
            XCTAssertEqual(d, .pick(preselected: def.id), s)
        }
    }
}
