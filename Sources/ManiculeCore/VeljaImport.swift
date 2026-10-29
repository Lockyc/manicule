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

    public static func result(fromPreferences plist: Data, targets: [Target], existing: [Rule]) -> Result {
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
            guard let rule = map(obj, targets: targets) else {
                skipped += 1
                continue
            }
            if (existing + out).contains(where: { same($0, rule) }) { continue }
            out.append(rule)
        }
        return Result(rules: out, skipped: skipped)
    }

    private static func same(_ a: Rule, _ b: Rule) -> Bool {
        a.matchers == b.matchers && a.sourceApp == b.sourceApp && a.target == b.target
    }

    private static func map(_ obj: [String: Any], targets: [Target]) -> Rule? {
        let matchers = (obj["matchers"] as? [[String: Any]] ?? []).compactMap { m -> Matcher? in
            guard let kind = m["kind"] as? String, let pattern = m["pattern"] as? String else { return nil }
            switch kind {
            case "hostSuffix": return .hostSuffix(pattern)
            case "hostExact", "host": return .hostExact(pattern)
            case "urlContains": return .urlContains(pattern)
            default: return nil
            }
        }
        guard !matchers.isEmpty else { return nil }
        let sources = obj["sourceApps"] as? [String] ?? []
        guard sources.count <= 1 else { return nil }
        let raw = (obj["openTarget"] as? String).map { $0.hasPrefix("browser:") ? String($0.dropFirst(8)) : $0 }
            ?? obj["browser"] as? String
        guard let raw, let target = target(for: raw, in: targets) else { return nil }
        return Rule(title: obj["title"] as? String ?? "Imported from Velja", matchers: matchers,
                    sourceApp: sources.first, target: target.id)
    }

    private static func target(for spec: String, in targets: [Target]) -> Target? {
        let parts = spec.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let bundle = String(parts[0])
        let ofBrowser = targets.filter { $0.browser.bundleID == bundle }
        if parts.count > 1, !parts[1].isEmpty {
            return ofBrowser.first { $0.profile == String(parts[1]) }
        }
        return ofBrowser.count == 1 ? ofBrowser[0] : nil
    }
}
