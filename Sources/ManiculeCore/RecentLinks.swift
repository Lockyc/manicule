import Foundation

/// One row of the menu bar's Recent submenu.
public struct RecentItem: Equatable, Sendable {
    public static let unresolvedTargetName = "Copied or cancelled"
    public static let limit = 20

    public let title: String
    public let tooltip: String
    public let entry: HistoryEntry

    /// Newest first, at most `limit`; history is stored oldest first. A link that was opened is titled
    /// with `name` of its target (a flotilla group or a gone target included); only one never opened
    /// says `unresolvedTargetName`.
    public static func items(from config: Config, name: (Target.ID) -> String) -> [RecentItem] {
        config.history.suffix(limit).reversed().map { entry in
            let targetName = entry.target.map(name) ?? unresolvedTargetName
            let host = entry.url.host ?? entry.url.absoluteString
            return RecentItem(title: "\(host) — \(targetName)", tooltip: entry.url.absoluteString, entry: entry)
        }
    }
}
