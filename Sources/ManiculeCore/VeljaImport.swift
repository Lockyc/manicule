import Foundation

/// Reads Velja's preferences plist: a `rules` array whose elements are JSON strings.
public enum VeljaImport {
    public struct Result: Equatable, Sendable {
        /// Rules to append: mappable, enabled and not already present.
        public var rules: [Rule]
        /// Enabled Velja rules Manicule can't express (unknown matchers, several source apps, no single target).
        public var skipped: Int
    }

    public static func rules(fromPreferences plist: Data, targets: [Target]) -> [Rule] {
        result(fromPreferences: plist, targets: targets, existing: []).rules
    }

    /// `defaultTargets`: each browser's own default profile, which a profile-less Velja target
    /// names when the browser has several.
    public static func result(fromPreferences plist: Data, targets: [Target], existing: [Rule],
                              defaultTargets: Set<Target.ID> = []) -> Result {
        guard let root = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
              let strings = root["rules"] as? [String] else { return Result(rules: [], skipped: 0) }
        var out: [Rule] = []
        var skipped = 0
        for string in strings {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(string.utf8)) as? [String: Any] else {
                skipped += 1
                continue
            }
            if obj["isEnabled"] as? Bool == false { continue }
            let rules = map(obj, targets: targets, defaultTargets: defaultTargets)
            if rules.isEmpty { skipped += 1 }
            for rule in rules where !(existing + out).contains(where: { same($0, rule) }) {
                out.append(rule)
            }
        }
        return Result(rules: out, skipped: skipped)
    }

    private static func same(_ a: Rule, _ b: Rule) -> Bool {
        a.matchers == b.matchers && a.sourceApp == b.sourceApp && a.target == b.target
    }

    /// Velja's matchers are alternatives (any one matches) while a Manicule rule needs all of its
    /// matchers, so each mappable Velja matcher becomes its own rule.
    private static func map(_ obj: [String: Any], targets: [Target], defaultTargets: Set<Target.ID>) -> [Rule] {
        let matchers = (obj["matchers"] as? [[String: Any]] ?? []).compactMap { m -> Matcher? in
            guard let kind = m["kind"] as? String, let pattern = m["pattern"] as? String else { return nil }
            switch kind {
            case "hostSuffix": return .hostSuffix(pattern)
            case "hostExact", "host": return .hostExact(pattern)
            case "urlContains": return .urlContains(pattern)
            default: return nil
            }
        }
        let sources = obj["sourceApps"] as? [String] ?? []
        let prefix = "browser:"
        let raw = (obj["openTarget"] as? String).map { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : $0 }
            ?? obj["browser"] as? String
        guard !matchers.isEmpty, sources.count <= 1, let raw, let target = target(for: raw, in: targets, defaults: defaultTargets) else { return [] }
        let title = obj["title"] as? String ?? "Imported from Velja"
        return matchers.enumerated().map { i, m in
            Rule(title: i == 0 ? title : "\(title) (\(i + 1))", matchers: [m], sourceApp: sources.first, target: target.id)
        }
    }

    private static func target(for spec: String, in targets: [Target], defaults: Set<Target.ID>) -> Target? {
        let parts = spec.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let bundle = String(parts[0])
        let ofBrowser = targets.filter { $0.browser.bundleID == bundle }
        if parts.count > 1, !parts[1].isEmpty {
            return ofBrowser.first { $0.profile == String(parts[1]) }
        }
        if ofBrowser.count == 1 { return ofBrowser[0] }
        let defaulted = ofBrowser.filter { defaults.contains($0.id) }
        return defaulted.count == 1 ? defaulted[0] : nil
    }
}
