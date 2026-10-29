import Foundation

/// One URL condition. `Codable` via synthesised enum coding, so rules persist as JSON.
public enum Matcher: Codable, Hashable, Sendable {
    case hostExact(String)
    case hostSuffix(String)
    case pathContains(String)
    case queryContains(String)
    case urlContains(String)
    case regex(String)

    /// Host matchers never match a URL without a host (file://); an invalid regex never matches.
    public func matches(_ url: URL) -> Bool {
        switch self {
        case .hostExact(let h):
            guard let host = Self.host(of: url), !h.isEmpty else { return false }
            return host == h.lowercased()
        case .hostSuffix(let s):
            guard let host = Self.host(of: url), !s.isEmpty else { return false }
            let suffix = s.lowercased()
            return host == suffix || host.hasSuffix("." + suffix)
        case .pathContains(let p):
            return url.path.contains(p)
        case .queryContains(let q):
            return (url.query ?? "").contains(q)
        case .urlContains(let u):
            return url.absoluteString.contains(u)
        case .regex(let pattern):
            guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
            let s = url.absoluteString
            return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
        }
    }

    /// A matcher's case without its value, for editing one as (kind, text).
    public enum Kind: String, CaseIterable, Sendable {
        case hostExact, hostSuffix, pathContains, queryContains, urlContains, regex

        public var title: String {
            switch self {
            case .hostExact: "Host is"
            case .hostSuffix: "Host ends with"
            case .pathContains: "Path contains"
            case .queryContains: "Query contains"
            case .urlContains: "URL contains"
            case .regex: "URL matches regex"
            }
        }
    }

    public init(kind: Kind, value: String) {
        switch kind {
        case .hostExact: self = .hostExact(value)
        case .hostSuffix: self = .hostSuffix(value)
        case .pathContains: self = .pathContains(value)
        case .queryContains: self = .queryContains(value)
        case .urlContains: self = .urlContains(value)
        case .regex: self = .regex(value)
        }
    }

    public var kind: Kind {
        switch self {
        case .hostExact: .hostExact
        case .hostSuffix: .hostSuffix
        case .pathContains: .pathContains
        case .queryContains: .queryContains
        case .urlContains: .urlContains
        case .regex: .regex
        }
    }

    public var value: String {
        switch self {
        case .hostExact(let v), .hostSuffix(let v), .pathContains(let v),
             .queryContains(let v), .urlContains(let v), .regex(let v): v
        }
    }

    private static func host(of url: URL) -> String? {
        guard let h = url.host?.lowercased(), !h.isEmpty else { return nil }
        return h
    }
}

public struct Rule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var matchers: [Matcher]
    public var sourceApp: String?
    public var target: String
    public var isEnabled: Bool

    public init(id: UUID = UUID(), title: String, matchers: [Matcher], sourceApp: String? = nil,
                target: String, isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.matchers = matchers
        self.sourceApp = sourceApp
        self.target = target
        self.isEnabled = isEnabled
    }

    /// `id` and `target` are required; any other missing key takes its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id),
                  title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
                  matchers: try c.decodeIfPresent([Matcher].self, forKey: .matchers) ?? [],
                  sourceApp: try c.decodeIfPresent(String.self, forKey: .sourceApp),
                  target: try c.decode(String.self, forKey: .target),
                  isEnabled: try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true)
    }

    /// Enabled, at least one matcher, source app (when set) equal, and every matcher holds. A rule
    /// with no matchers never matches: emptying one while editing must not open every link silently.
    public func matches(url: URL, sourceApp: String?) -> Bool {
        guard isEnabled, !matchers.isEmpty else { return false }
        if let required = self.sourceApp, required != sourceApp { return false }
        return matchers.allSatisfy { $0.matches(url) }
    }

    /// The picker's ⌥⏎: always open this host (and its subdomains) in `target`.
    public static func always(host: String, target: String) -> Rule {
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return Rule(title: "\(host) → \(target)", matchers: [.hostSuffix(bare)], target: target)
    }

    /// A rule added in Settings: one empty condition, off until the user fills it in and turns it on.
    public static func new(target: String) -> Rule {
        Rule(title: "New rule", matchers: [.hostSuffix("")], target: target, isEnabled: false)
    }

    /// At least one condition has a value; only then can the rule be turned on.
    public var hasCondition: Bool {
        matchers.contains { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
