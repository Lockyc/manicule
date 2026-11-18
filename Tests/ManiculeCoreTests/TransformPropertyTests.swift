import Exhaust
import XCTest
@testable import ManiculeCore

/// Round-trip and uniqueness rules for the URL and launcher-id transforms, over generated inputs.
final class TransformPropertyTests: XCTestCase {
    // MARK: Tracking parameters

    static let queryNames = ["q", "a", "next", "utm_source", "UTM_Medium", "utm%5Fcampaign", "fbclid", "FBCLID",
                             "gclid", "mc_eid", "pk_kwd", "hsa_acc", "_hsenc", "ref_src", "utm", "refsrc", "x%20y"]
    static let queryValues = ["", "1", "a%2Bb", "a+b", "%2Fx%3Fy%3D1", "%3F", "%26", "%25", "caf%C3%A9", "="]

    static let queryItem = #gen(.element(from: queryNames), .element(from: queryValues).optional(someWeight: 4, noneWeight: 1))
        .map { name, value in value.map { "\(name)=\($0)" } ?? name }

    static let trackedURL = #gen(queryItem.array(length: 0...6), .element(from: ["", "#frag", "#a?b=c"])).map { items, fragment in
        URL(string: "https://example.com/p" + (items.isEmpty ? "" : "?" + items.joined(separator: "&")) + fragment)!
    }

    private static func query(_ url: URL) -> [URLQueryItem] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems ?? []
    }

    private static func isTracking(_ name: String) -> Bool {
        let lower = (name.removingPercentEncoding ?? name).lowercased()
        return TrackingParameters.names.contains(lower) || TrackingParameters.prefixes.contains { lower.hasPrefix($0) }
    }

    /// Kept parameters are the original's, byte for byte and in order; no tracking one survives;
    /// stripping is idempotent.
    func testStrippingKeepsTheRestVerbatimAndIsIdempotent() {
        #exhaust(Self.trackedURL, .budget(.thorough)) { url in
            let stripped = TrackingParameters.stripped(url)
            let kept = Self.query(stripped)
            return kept == Self.query(url).filter { !Self.isTracking($0.name) }
                && !kept.contains { Self.isTracking($0.name) }
                && TrackingParameters.stripped(stripped) == stripped
                && stripped.fragment == url.fragment
        }
    }

    // MARK: Google links

    static let googleHosts = ["docs.google.com", "drive.google.com", "DOCS.google.com", "forms.google.com",
                              "maps.google.com", "play.google.com", "www.google.com", "google.com", "example.com"]
    static let segments = ["document", "spreadsheets", "presentation", "forms", "file", "drive", "folders", "d", "e",
                           "u", "0", "edit", "open", "view", "store", "apps", "details", "maps", "place",
                           "1DocAbCdEfGhIjKlMnOpQrStUvWxYz0123456789", "shortid", "com.example.app", "a%2Fb"]

    /// The id-bearing shapes, with `ID` for the id: random segments alone almost never line one
    /// up, so a host check could go missing unnoticed.
    static let shapes = [["document", "d", "ID", "edit"], ["spreadsheets", "d", "ID"], ["file", "d", "ID", "view"],
                         ["forms", "d", "e", "ID", "viewform"], ["u", "0", "presentation", "d", "ID"],
                         ["drive", "folders", "ID"], ["drive", "u", "0", "folders", "ID"], ["open"], ["d", "e", "ID"]]

    static let path = #gen(.element(from: shapes), .element(from: ["1DocAbCdEfGhIjKlMnOpQrStUvWxYz0123456789",
                                                                   "1Doc-AbCd_EfGhIjKlMnOpQr", "shortid", "a%2Fb"]),
                           .element(from: segments).array(length: 0...6), .bool())
        .map { shape, id, random, shaped in shaped ? shape.map { $0 == "ID" ? id : $0 } : random }

    static let googleURL = #gen(.element(from: googleHosts), path,
                                .element(from: ["", "?id=1DocAbCdEfGhIjKlMnOpQrStUvWxYz0123456789", "?id=e",
                                                "?usp=sharing", "?authuser=a%40example.com"]))
        .map { host, path, query in URL(string: "https://\(host)/" + path.joined(separator: "/") + query)! }

    /// A file id comes only from a Docs or Drive host and always looks like a Drive id.
    func testFileIDsComeOnlyFromDocsOrDriveAndLookLikeDriveIDs() {
        #exhaust(Self.googleURL, .budget(.thorough)) { url in
            guard let id = GoogleLink(url: url)?.fileID else { return true }
            let host = url.host?.lowercased()
            return (host == "docs.google.com" || host == "drive.google.com")
                && id.count >= 20
                && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        }
    }

    // MARK: Launchers

    static let launcherTarget = #gen(.element(from: [Browser.chrome, .chromium, .firefox]),
                                     .element(from: ["Default", "Profile 1", "Profile 2", "Profile 10"]),
                                     .element(from: ["Chrome · Work", "Chrome · Home", "Chromium · Work", "Work", "work", "Home"]),
                                     .element(from: [WebApp.docs, .sheets, .slides].map(\.chromeAppID)).set(count: 0...3))
        .map { browser, dir, name, apps in
            (Target(id: "\(browser.rawValue)|\(dir)", browser: browser, profile: dir, name: name, email: nil),
             DiscoveredProfile(browser: browser, directory: dir, name: dir, email: nil, installedWebApps: apps))
        }

    /// Visible targets with distinct ids (as a config holds them) and the profiles they came from.
    static let launcherInput = launcherTarget.array(length: 0...6).map { pairs in
        var seen = Set<Target.ID>()
        let unique = pairs.filter { seen.insert($0.0.id).inserted }
        return (unique.map(\.0), unique.map(\.1))
    }

    /// No two launchers share a bundle id or a name (case-insensitively, as the disk compares
    /// file names), and each target's launchers read back as that target's browser.
    func testLaunchersHaveUniqueIdsAndNamesAndReadBackTheirBrowser() {
        #exhaust(Self.launcherInput, .budget(.thorough)) { visible, profiles in
            let specs = LauncherSpecs.make(visible: visible, profiles: profiles)
            return Set(specs.map(\.bundleID)).count == specs.count
                && Set(specs.map { $0.appName.lowercased() }).count == specs.count
                && visible.allSatisfy { target in
                    let own = profiles.filter { $0.targetID == target.id }
                    return LauncherSpecs.make(visible: visible, profiles: own)
                        .allSatisfy { LauncherSpecs.browser(fromBundleID: $0.bundleID) == target.browser }
                }
        }
    }

    // MARK: Flotilla groups

    static let flotillaWindow = #gen(.element(from: ["Club", "club", "A|B", "A", "B", "Cafe", "Café"]),
                                     .element(from: ["Bulletins", "Minutes", "A|B", "B", "A", "x%20y", "x y"])
                                         .array(length: 0...4))
        .map { title, groups in FlotillaWindow(title: title, colour: nil, groups: groups) }

    /// Group ids are unique, and each parses back to its own window and group.
    func testFlotillaGroupIdsAreUniqueAndParseBack() {
        #exhaust(Self.flotillaWindow.array(length: 0...4), .budget(.thorough)) { windows in
            let groups = Flotilla.groupTargets(windows)
            let pairs = Set(windows.flatMap { w in w.groups.map { "\(w.title)\u{0}\($0)" } })
            return Set(groups.map(\.id)).count == groups.count
                && groups.count == pairs.count
                && groups.allSatisfy { g in
                    let (window, group) = Flotilla.parse(g.id)
                    return g.id == Flotilla.groupID(window: window ?? "", group: group ?? "")
                }
        }
    }
}
