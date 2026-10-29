import Foundation

/// One resolved link: the target opened, or nil when it was copied or cancelled.
public struct HistoryEntry: Codable, Equatable, Sendable {
    public var url: URL
    public var sourceApp: String?
    public var target: Target.ID?
    public var at: Date

    public init(url: URL, sourceApp: String?, target: Target.ID?, at: Date) {
        self.url = url
        self.sourceApp = sourceApp
        self.target = target
        self.at = at
    }
}

public struct Config: Codable, Equatable, Sendable {
    public static let historyLimit = 100

    public var targets: [Target]
    public var visible: [Target.ID]
    public var rules: [Rule]
    public var rememberedDocuments: [String: Target.ID]
    public var lastChoiceByHost: [String: Target.ID]
    public var history: [HistoryEntry]

    public init(targets: [Target], visible: [Target.ID], rules: [Rule] = [],
                rememberedDocuments: [String: Target.ID] = [:],
                lastChoiceByHost: [String: Target.ID] = [:], history: [HistoryEntry] = []) {
        self.targets = targets
        self.visible = visible
        self.rules = rules
        self.rememberedDocuments = rememberedDocuments
        self.lastChoiceByHost = lastChoiceByHost
        self.history = history
    }

    public var routerState: RouterState {
        RouterState(targets: targets, visible: visible, rules: rules,
                    rememberedDocuments: rememberedDocuments, lastChoiceByHost: lastChoiceByHost)
    }
}

extension Config {
    /// One target per discovered profile, all visible.
    public static func defaults(from discovered: [DiscoveredProfile]) -> Config {
        let firefoxCount = discovered.filter { $0.browser == .firefox }.count
        let targets = discovered.map { p -> Target in
            let name: String
            switch p.browser {
            case .chrome: name = "Chrome · \(p.name)"
            case .chromium: name = "Chromium · \(p.name)"
            case .firefox: name = firefoxCount > 1 ? "Firefox · \(p.name)" : "Firefox"
            case .safari: name = "Safari"
            }
            return Target(id: "\(p.browser.rawValue)|\(p.directory)", browser: p.browser,
                          profile: p.directory.isEmpty ? nil : p.directory, name: name, email: p.email)
        }
        return Config(targets: targets, visible: targets.map(\.id))
    }

    /// Learns from a deliberate pick: last choice for the host, the document, and optionally an always-rule.
    public mutating func recordPick(_ link: IncomingLink, target: Target.ID, always: Bool) {
        let host = link.url.host?.lowercased()
        if let host, !host.isEmpty {
            lastChoiceByHost[host] = target
            if always { rules.append(.always(host: host, target: target)) }
        }
        if let fileID = GoogleLink(url: link.url)?.fileID {
            rememberedDocuments[fileID] = target
        }
    }

    /// Appends to history, dropping the oldest beyond `historyLimit`.
    public mutating func recordOutcome(_ link: IncomingLink, target: Target.ID?) {
        history.append(HistoryEntry(url: link.url, sourceApp: link.sourceApp, target: target, at: link.receivedAt))
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
    }
}
