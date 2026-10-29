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
}

public struct RouterState: Sendable {
    public var targets: [Target]
    public var visible: [Target.ID]
    public var rules: [Rule]
    public var rememberedDocuments: [String: Target.ID]
    public var lastChoiceByHost: [String: Target.ID]
    /// Targets that can open on this Mac now (see `Config.available`); every other target is
    /// treated as dangling.
    public var available: Set<Target.ID>

    public init(targets: [Target], visible: [Target.ID], rules: [Rule],
                rememberedDocuments: [String: Target.ID], lastChoiceByHost: [String: Target.ID],
                available: Set<Target.ID>) {
        self.targets = targets
        self.visible = visible
        self.rules = rules
        self.rememberedDocuments = rememberedDocuments
        self.lastChoiceByHost = lastChoiceByHost
        self.available = available
    }

    /// The target with this id, when it exists and is available.
    public func target(_ id: Target.ID?) -> Target? {
        guard let id, available.contains(id) else { return nil }
        return targets.first { $0.id == id }
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
    case accountEmail, rule(UUID), rememberedDocument
}

public enum Decision: Equatable, Sendable {
    case open(Target, Reason)
    case pick(preselected: Target.ID?)
}

public enum Router {
    /// Account email, then rules, then remembered document, then the picker. A step naming a
    /// target that no longer exists, or isn't available, falls through rather than opening it.
    public static func decide(_ link: IncomingLink, state: RouterState) -> Decision {
        let google = GoogleLink(url: link.url)

        if let email = google?.email,
           let t = state.targets.first(where: { $0.email?.lowercased() == email && state.available.contains($0.id) }) {
            return .open(t, .accountEmail)
        }

        for rule in state.rules where rule.matches(url: link.url, sourceApp: link.sourceApp) {
            if let t = state.target(rule.target) { return .open(t, .rule(rule.id)) }
        }

        if let fileID = google?.fileID, let t = state.target(state.rememberedDocuments[fileID]) {
            return .open(t, .rememberedDocument)
        }

        let host = link.url.host?.lowercased().nilIfEmpty
        if let host, let last = state.target(state.lastChoiceByHost[host]) {
            return .pick(preselected: last.id)
        }
        return .pick(preselected: state.pickerTargets.first?.id)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
