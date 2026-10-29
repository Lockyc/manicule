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

    /// Enabled, source app (when set) equal, and every matcher holds.
    public func matches(url: URL, sourceApp: String?) -> Bool {
        guard isEnabled else { return false }
        if let required = self.sourceApp, required != sourceApp { return false }
        return matchers.allSatisfy { $0.matches(url) }
    }

    /// The picker's ⌥⏎: always open this host (and its subdomains) in `target`.
    public static func always(host: String, target: String) -> Rule {
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return Rule(title: "\(host) → \(target)", matchers: [.hostSuffix(bare)], target: target)
    }
}
