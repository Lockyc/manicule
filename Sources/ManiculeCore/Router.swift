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

    /// The picker strip: visible targets that are available, in the user's order.
    public var pickerTargets: [Target] {
        visible.compactMap(target)
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

        let visible = state.pickerTargets.map(\.id)
        let host = link.url.host?.lowercased().nilIfEmpty
        if let host, let last = state.lastChoiceByHost[host], visible.contains(last) {
            return .pick(preselected: last)
        }
        return .pick(preselected: visible.first)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
