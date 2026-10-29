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

    /// Tolerates a config from another version: a missing key takes its default (`visible`
    /// defaults to every target), an unknown key is ignored.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let targets = try c.decodeIfPresent([Target].self, forKey: .targets) ?? []
        self.init(targets: targets,
                  visible: try c.decodeIfPresent([Target.ID].self, forKey: .visible) ?? targets.map(\.id),
                  rules: try c.decodeIfPresent([Rule].self, forKey: .rules) ?? [],
                  rememberedDocuments: try c.decodeIfPresent([String: Target.ID].self, forKey: .rememberedDocuments) ?? [:],
                  lastChoiceByHost: try c.decodeIfPresent([String: Target.ID].self, forKey: .lastChoiceByHost) ?? [:],
                  history: try c.decodeIfPresent([HistoryEntry].self, forKey: .history) ?? [])
    }

    public func routerState(available: Set<Target.ID>) -> RouterState {
        RouterState(targets: targets, visible: visible, rules: rules,
                    rememberedDocuments: rememberedDocuments, lastChoiceByHost: lastChoiceByHost,
                    available: available)
    }

    /// Targets that can open on this Mac: found by this discovery, or in a browser whose profile
    /// file can't be read yet (unknown, so not penalised).
    public func available(discovered: [DiscoveredProfile], unreadable: [Browser]) -> Set<Target.ID> {
        let found = Set(discovered.map(\.targetID))
        return Set(targets.filter { found.contains($0.id) || unreadable.contains($0.browser) }.map(\.id))
    }
}

extension Config {
    /// One target per discovered profile, all visible.
    public static func defaults(from discovered: [DiscoveredProfile]) -> Config {
        let firefoxCount = discovered.filter { $0.browser == .firefox }.count
        let separator = Target.nameSeparator
        let targets = discovered.map { p -> Target in
            let browser = p.browser.displayName
            let name: String
            switch p.browser {
            case .chrome, .chromium: name = "\(browser)\(separator)\(p.name)"
            case .firefox: name = firefoxCount > 1 ? "\(browser)\(separator)\(p.name)" : browser
            case .safari: name = browser
            }
            return Target(id: p.targetID, browser: p.browser,
                          profile: p.directory.isEmpty ? nil : p.directory, name: name, email: p.email)
        }
        return Config(targets: targets, visible: targets.map(\.id))
    }

    /// Folds a later discovery in: unknown profiles are appended hidden, known targets take the
    /// discovered email. Names, order and `visible` are the user's; no target is ever removed.
    public mutating func merge(discovered: [DiscoveredProfile]) {
        for found in Config.defaults(from: discovered).targets {
            if let index = targets.firstIndex(where: { $0.id == found.id }) {
                targets[index].email = found.email
            } else {
                targets.append(found)
            }
        }
    }

    /// Shows or hides a target in the picker. `visible` follows `targets` order, so the picker's
    /// order is the order the user arranges targets in.
    public mutating func setVisible(_ id: Target.ID, _ isVisible: Bool) {
        var shown = Set(visible)
        if isVisible { shown.insert(id) } else { shown.remove(id) }
        visible = targets.map(\.id).filter(shown.contains)
    }

    /// Reorders targets (List.onMove's arguments); `visible` follows.
    public mutating func moveTargets(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { targets[$0] }
        var rest = targets.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        rest.insert(contentsOf: moving, at: destination - source.filter { $0 < destination }.count)
        targets = rest
        let shown = Set(visible)
        visible = targets.map(\.id).filter(shown.contains)
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
