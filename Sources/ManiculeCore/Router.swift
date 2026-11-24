import Foundation

public struct IncomingLink: Equatable, Sendable {
    public var url: URL
    public var sourceApp: String?
    public var receivedAt: Date

    public init(url: URL, sourceApp: String?, receivedAt: Date) {
        self.url = url
        self.sourceApp = sourceApp
        self.receivedAt = receivedAt
    }

    /// Web links and local files (HTML documents opened with Manicule as the default browser).
    public static func isHandled(_ url: URL) -> Bool {
        ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "")
    }

    /// The key for per-host last choices and ⌥⏎ rules: the lowercased host, nil when the link has
    /// none (a `file` URL), so no host rule or host memory applies to it.
    public var hostKey: String? {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        return host
    }
}

public struct RouterState: Sendable {
    public var targets: [Target]
    public var visible: [Target.ID]
    public var rules: [Rule]
    public var lastChoiceByDocument: [String: Target.ID]
    public var lastChoiceByHost: [String: Target.ID]
    /// Targets that can open on this Mac now (see `Config.available`); every other target is
    /// treated as dangling.
    public var available: Set<Target.ID>

    public init(targets: [Target], visible: [Target.ID], rules: [Rule],
                lastChoiceByDocument: [String: Target.ID], lastChoiceByHost: [String: Target.ID],
                available: Set<Target.ID>) {
        self.targets = targets
        self.visible = visible
        self.rules = rules
        self.lastChoiceByDocument = lastChoiceByDocument
        self.lastChoiceByHost = lastChoiceByHost
        self.available = available
    }

    /// The target with this id, when it exists and is available. A flotilla group that is gone
    /// still opens in flotilla while flotilla is available, under a "(closed)" name.
    public func target(_ id: Target.ID?) -> Target? {
        guard let id else { return nil }
        if available.contains(id), let found = targets.first(where: { $0.id == id }) { return found }
        guard available.contains(Flotilla.plainID), case let (window?, group?) = Flotilla.parse(id) else { return nil }
        return Target(id: id, browser: .flotilla, profile: nil,
                      name: Flotilla.groupName(window: window, group: group) + Flotilla.closedSuffix, email: nil)
    }

    /// The picker strip: pinned targets that are available, in `targets` order.
    public var pickerTargets: [Target] {
        let pinned = Set(visible)
        return targets.filter { pinned.contains($0.id) && available.contains($0.id) }
    }

    /// The strip, one group per browser.
    public var pickerGroups: [[Target]] { Target.groupedByBrowser(pickerTargets) }

    /// The ⋯ menu: available targets that aren't pinned, one group per browser.
    public var overflowGroups: [[Target]] {
        let pinned = Set(visible)
        return Target.groupedByBrowser(targets.filter { !pinned.contains($0.id) && available.contains($0.id) })
    }
}

public enum Reason: Equatable, Sendable {
    case accountEmail, rule(UUID)
}

public enum Decision: Equatable, Sendable {
    case open(Target, Reason)
    case pick(preselected: Target.ID?)
}

public enum Router {
    /// Account email, then rules, then the picker — preselecting the last choice for the Google
    /// document, else for the host, else the first tile of the link's `pickerLayout`. A step
    /// naming a target that no longer exists, or isn't available, falls through rather than
    /// opening it; a last choice counts only when the link's layout shows it.
    ///
    /// A Meet link's email matches only cooee profiles while cooee is available; any other link's
    /// email matches only non-cooee targets, and a rule naming a cooee target applies to Meet
    /// links alone.
    public static func decide(_ link: IncomingLink, state: RouterState) -> Decision {
        let google = GoogleLink(url: link.url)
        let meet = Cooee.isMeet(link.url)
        let toCooee = meet && !cooeeTargets(state).isEmpty

        if let email = google?.email,
           let t = state.targets.first(where: {
               ($0.browser == .cooee) == toCooee && $0.email?.lowercased() == email && state.available.contains($0.id)
           }) {
            return .open(t, .accountEmail)
        }

        for rule in state.rules where rule.matches(url: link.url, sourceApp: link.sourceApp) {
            if let t = state.target(rule.target), meet || t.browser != .cooee { return .open(t, .rule(rule.id)) }
        }

        let layout = pickerLayout(link, state: state)
        let shown = Set((layout.strip + layout.more).joined().map(\.id))
        let lastChoices = [google?.fileID.flatMap { state.lastChoiceByDocument[$0] },
                           link.hostKey.flatMap { state.lastChoiceByHost[$0] }]
        if let last = lastChoices.lazy.compactMap({ $0 }).first(where: shown.contains) {
            return .pick(preselected: last)
        }
        return .pick(preselected: layout.strip.first?.first?.id)
    }

    /// The picker's strip and ⋯ menu for `link`. A Meet link with cooee available puts every cooee
    /// profile on the strip, pinned or not (plain cooee when there are none), and every other
    /// available target under ⋯; any other link gets the pinned strip and ⋯ without cooee.
    public static func pickerLayout(_ link: IncomingLink, state: RouterState) -> (strip: [[Target]], more: [[Target]]) {
        let cooee = cooeeTargets(state)
        guard Cooee.isMeet(link.url), !cooee.isEmpty else {
            func withoutCooee(_ groups: [[Target]]) -> [[Target]] {
                groups.filter { $0.first?.browser != .cooee }
            }
            return (withoutCooee(state.pickerGroups), withoutCooee(state.overflowGroups))
        }
        let profiles = cooee.filter { $0.id != Cooee.plainID }
        let strip = profiles.isEmpty ? cooee.filter { $0.id == Cooee.plainID } : profiles
        let shown = Set(strip.map(\.id))
        let more = state.targets.filter { state.available.contains($0.id) && !shown.contains($0.id) }
        return ([strip], Target.groupedByBrowser(more))
    }

    /// The available cooee targets, in `targets` order.
    private static func cooeeTargets(_ state: RouterState) -> [Target] {
        state.targets.filter { $0.browser == .cooee && state.available.contains($0.id) }
    }
}
