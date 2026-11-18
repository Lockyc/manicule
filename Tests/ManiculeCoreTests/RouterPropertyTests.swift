import Exhaust
import XCTest
@testable import ManiculeCore

/// The routing rules CLAUDE.md and `Router.decide`'s docblock state for every input, checked over
/// generated states and links rather than one example each.
final class RouterPropertyTests: XCTestCase {
    static let doc = "1DocAbCdEfGhIjKlMnOpQrStUvWxYz0123456789"

    /// Every target kind, the plain flotilla and cooee targets, a flotilla group, and accounts
    /// shared across kinds so step 1 has a choice to get wrong.
    static let universe: [Target] = [
        Target(id: "chrome|Default", browser: .chrome, profile: "Default", name: "Chrome · Work", email: "a@example.com"),
        Target(id: "chrome|Profile 1", browser: .chrome, profile: "Profile 1", name: "Chrome · Home", email: "b@example.com"),
        Target(id: "chromium|Default", browser: .chromium, profile: "Default", name: "Chromium · Work", email: "a@example.com"),
        Target(id: "firefox|", browser: .firefox, profile: nil, name: "Firefox", email: nil),
        Target(id: "safari|", browser: .safari, profile: nil, name: "Safari", email: nil),
        Target(id: Flotilla.plainID, browser: .flotilla, profile: nil, name: "flotilla", email: nil),
        Target(id: Flotilla.windowID("Club"), browser: .flotilla, profile: nil, name: "flotilla · Club", email: nil),
        Target(id: Flotilla.groupID(window: "Club", group: "Bulletins"), browser: .flotilla, profile: nil,
               name: "flotilla · Club ▸ Bulletins", email: nil),
        Target(id: Cooee.plainID, browser: .cooee, profile: nil, name: "cooee", email: nil),
        Target(id: Cooee.profileID("Work"), browser: .cooee, profile: nil, name: "cooee · Work", email: "a@example.com"),
        Target(id: Cooee.profileID("Home"), browser: .cooee, profile: nil, name: "cooee · Home", email: "b@example.com"),
    ]

    /// Ids a rule or last choice may name: every target, a gone flotilla group, and a target that
    /// no longer exists.
    static let ids = universe.map(\.id) + [Flotilla.groupID(window: "Gone", group: "Old"), "chrome|Deleted"]

    static let hosts = ["meet.google.com", "MEET.Google.com", "docs.google.com", "drive.google.com",
                        "example.com", "www.example.com", "google.com"]

    /// Weighted towards values that hold for many links, so rules fire often enough to test.
    static let matcherValues = ["", " ", "meet.google.com", "google.com", "google.com", "example.com", "com", "com", "com",
                                "o", "o", "docs", ".", ".", "^https:", "authuser", "["]

    static let matcher = #gen(.element(from: Matcher.Kind.allCases), .element(from: matcherValues)) { kind, value in
        Matcher(kind: kind, value: value)
    }

    static let rule = #gen(matcher.array(length: 0...2),
                           .element(from: ["com.apple.mail", "com.tinyspeck.slackmacgap"]).optional(someWeight: 1, noneWeight: 4),
                           .element(from: ids), .bool()).map { matchers, app, target, enabled in
        Rule(title: "r", matchers: matchers, sourceApp: app, target: target, isEnabled: enabled)
    }

    static func subset(_ ids: [String]) -> ReflectiveGenerator<[String]> {
        #gen(.bool().array(length: ids.count...ids.count)).map { picks in
            zip(ids, picks).filter(\.1).map(\.0)
        }
    }

    static let state = #gen(subset(universe.map(\.id)), subset(universe.map(\.id)), subset(universe.map(\.id)),
                            rule.array(length: 0...3), .element(from: ids).optional(), .element(from: ids).optional(),
                            .element(from: hosts)).map { present, visible, available, rules, lastDoc, lastHost, host in
        RouterState(targets: universe.filter { present.contains($0.id) }, visible: visible, rules: rules,
                    lastChoiceByDocument: lastDoc.map { [doc: $0] } ?? [:],
                    lastChoiceByHost: lastHost.map { [host.lowercased(): $0] } ?? [:],
                    available: Set(available))
    }

    static let paths = ["/", "/abc-defg-hij", "/document/d/\(doc)/edit", "/u/a@example.com/", "/u/1/",
                        "/document/d/\(doc)/edit?authuser=b%40example.com", "/?authuser=a@example.com"]

    static let url = #gen(.element(from: ["https", "http", "HTTPS", "file"]), .element(from: hosts),
                          .element(from: paths)).map { scheme, host, path in
        URL(string: scheme == "file" ? "file:///tmp/page.html" : "\(scheme)://\(host)\(path)")!
    }

    static let link = #gen(url, .element(from: ["com.apple.mail", "com.tinyspeck.slackmacgap"]).optional()).map { url, app in
        IncomingLink(url: url, sourceApp: app, receivedAt: Date(timeIntervalSince1970: 0))
    }

    /// A preselection is a tile the link's own picker shows; an opened target is available (or a
    /// flotilla group while flotilla is), and cooee opens only a Meet link.
    func testDecisionStaysInsideTheLinksPickerAndAvailability() {
        #exhaust(#gen(Self.state, Self.link), .budget(.thorough)) { state, link in
            switch Router.decide(link, state: state) {
            case .pick(preselected: nil):
                return true
            case .pick(preselected: let p?):
                let layout = Router.pickerLayout(link, state: state)
                return (layout.strip + layout.more).joined().contains { $0.id == p }
            case .open(let t, _):
                let reachable = state.available.contains(t.id)
                    || (state.available.contains(Flotilla.plainID) && Flotilla.parse(t.id).group != nil)
                return reachable && (t.browser != .cooee || Cooee.isMeet(link.url))
            }
        }
    }

    /// A rule with no live condition never matches, whatever the URL and source app.
    func testARuleWithoutAConditionNeverMatches() {
        #exhaust(#gen(Self.rule, Self.link)) { rule, link in
            rule.hasCondition || !rule.matches(url: link.url, sourceApp: link.sourceApp)
        }
    }

    /// A rule that fires for a Meet link says it can match Meet, so Settings offers it cooee.
    func testARuleMatchingAMeetLinkCanMatchMeet() {
        #exhaust(#gen(Self.rule, Self.link)) { rule, link in
            !Cooee.isMeet(link.url) || !rule.matches(url: link.url, sourceApp: link.sourceApp) || rule.canMatchMeet
        }
    }

    /// Only an https link is a Meet link.
    func testOnlyHttpsIsMeet() {
        #exhaust(Self.url) { url in
            !Cooee.isMeet(url) || url.scheme?.lowercased() == "https"
        }
    }
}
