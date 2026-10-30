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

    /// Profile order within each browser; across browsers, `browserOrder` decides (see `orderedTargets`).
    public var targets: [Target]
    /// The pinned targets: in the picker strip. Every other available target is under ⋯.
    public var visible: [Target.ID]
    /// Every browser exactly once; the order of the picker's groups and Settings' sections.
    public var browserOrder: [Browser]
    public var rules: [Rule]
    public var rememberedDocuments: [String: Target.ID]
    public var lastChoiceByHost: [String: Target.ID]
    public var history: [HistoryEntry]

    /// A `browserOrder` that is missing browsers is completed by `completedBrowserOrder`.
    public init(targets: [Target], visible: [Target.ID], browserOrder: [Browser] = [], rules: [Rule] = [],
                rememberedDocuments: [String: Target.ID] = [:],
                lastChoiceByHost: [String: Target.ID] = [:], history: [HistoryEntry] = []) {
        self.targets = targets
        self.visible = visible
        self.browserOrder = Self.completedBrowserOrder(browserOrder, targets: targets)
        self.rules = rules
        self.rememberedDocuments = rememberedDocuments
        self.lastChoiceByHost = lastChoiceByHost
        self.history = history
    }

    /// Tolerates a config from another version: a missing key takes its default (`visible`
    /// defaults to every target), an unknown key or an unknown browser in `browserOrder` is ignored.
    /// A target with an unknown browser or a rule with an unknown matcher kind fails the decode, so
    /// `ConfigStore` moves the file aside rather than silently dropping them.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let targets = try c.decodeIfPresent([Target].self, forKey: .targets) ?? []
        let order = try c.decodeIfPresent([String].self, forKey: .browserOrder) ?? []
        self.init(targets: targets,
                  visible: try c.decodeIfPresent([Target.ID].self, forKey: .visible) ?? targets.map(\.id),
                  browserOrder: order.compactMap(Browser.init(rawValue:)),
                  rules: try c.decodeIfPresent([Rule].self, forKey: .rules) ?? [],
                  rememberedDocuments: try c.decodeIfPresent([String: Target.ID].self, forKey: .rememberedDocuments) ?? [:],
                  lastChoiceByHost: try c.decodeIfPresent([String: Target.ID].self, forKey: .lastChoiceByHost) ?? [:],
                  history: try c.decodeIfPresent([HistoryEntry].self, forKey: .history) ?? [])
    }

    /// `order` without repeats, then each browser in the order it first appears in `targets`,
    /// then the rest of `Browser.allCases`.
    public static func completedBrowserOrder(_ order: [Browser], targets: [Target]) -> [Browser] {
        var result: [Browser] = []
        for browser in order + targets.map(\.browser) + Browser.allCases where !result.contains(browser) {
            result.append(browser)
        }
        return result
    }

    /// The effective target order: browsers in `browserOrder`, each browser's profiles in `targets` order.
    public var orderedTargets: [Target] {
        browserOrder.flatMap(targets(of:))
    }

    public func targets(of browser: Browser) -> [Target] {
        targets.filter { $0.browser == browser }
    }

    /// Settings' sections: browsers with targets, plus `including` (installed or unreadable ones),
    /// in browser order.
    public func browserSections(including: Set<Browser>) -> [Browser] {
        let present = including.union(targets.map(\.browser))
        return browserOrder.filter(present.contains)
    }

    public func routerState(available: Set<Target.ID>) -> RouterState {
        RouterState(targets: orderedTargets, visible: visible, rules: rules,
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

    /// Pins or unpins a target. `visible` is kept in `orderedTargets` order.
    public mutating func setVisible(_ id: Target.ID, _ isVisible: Bool) {
        var shown = Set(visible)
        if isVisible { shown.insert(id) } else { shown.remove(id) }
        visible = orderedTargets.map(\.id).filter(shown.contains)
    }

    /// Puts `browser` where `destination` is, shifting the browsers between them one place.
    public mutating func moveBrowser(_ browser: Browser, to destination: Browser) {
        guard let from = browserOrder.firstIndex(of: browser),
              let to = browserOrder.firstIndex(of: destination), from != to else { return }
        browserOrder.remove(at: from)
        browserOrder.insert(browser, at: to)
        sortVisible()
    }

    /// Reorders one browser's profiles (List.onMove's arguments, as offsets into `targets(of:)`);
    /// other browsers' targets keep their places. Offsets outside the browser are ignored.
    public mutating func moveProfiles(of browser: Browser, fromOffsets source: IndexSet, toOffset destination: Int) {
        let slots = targets.indices.filter { targets[$0].browser == browser }
        guard source.allSatisfy(slots.indices.contains), (0...slots.count).contains(destination) else { return }
        var profiles = slots.map { targets[$0] }
        let moving = source.map { profiles[$0] }
        profiles = profiles.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        profiles.insert(contentsOf: moving, at: destination - source.filter { $0 < destination }.count)
        for (slot, profile) in zip(slots, profiles) { targets[slot] = profile }
        sortVisible()
    }

    private mutating func sortVisible() {
        let shown = Set(visible)
        visible = orderedTargets.map(\.id).filter(shown.contains)
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
