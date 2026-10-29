import Foundation

/// One row of the menu bar's Recent submenu.
public struct RecentItem: Equatable, Sendable {
    public static let unresolvedTargetName = "Copied or cancelled"
    public static let limit = 20

    public let title: String
    public let tooltip: String
    public let entry: HistoryEntry

    /// Newest first, at most `limit`; history is stored oldest first.
    public static func items(from config: Config) -> [RecentItem] {
        config.history.suffix(limit).reversed().map { entry in
            let targetName = entry.target.flatMap { id in config.targets.first { $0.id == id }?.name }
                ?? unresolvedTargetName
            let host = entry.url.host ?? entry.url.absoluteString
            return RecentItem(title: "\(host) — \(targetName)", tooltip: entry.url.absoluteString, entry: entry)
        }
    }
}
