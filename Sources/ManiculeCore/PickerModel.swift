import Foundation

/// A key the picker understands, already decoded from the raw event by the shell.
public enum PickerKey: Equatable, Sendable {
    /// 1-based position in the strip.
    case digit(Int)
    /// `0`: the ⋯ menu.
    case more
    case enter, optionEnter, copy, escape, left, right
}

/// The highlighted position in the strip: a pinned target, or the ⋯ tile at its end.
public enum PickerSelection: Equatable, Sendable {
    case target(Target.ID)
    case more
}

/// What a key leads to: the picker completes, or the ⋯ menu opens (the picker stays up).
public enum PickerStep: Equatable, Sendable {
    case finish(PickerAction)
    /// `highlighted` is the preselected target when it is in the menu.
    case showMore(highlighted: Target.ID?)
}

/// The picker's state and key handling, independent of any window.
public struct PickerModel: Sendable {
    public let link: IncomingLink
    /// Pinned targets, one group per browser.
    public let strip: [[Target]]
    /// Available targets that aren't pinned, one group per browser: the ⋯ menu.
    public let more: [[Target]]
    /// The preselection when it is in the menu rather than the strip.
    public let moreHighlight: Target.ID?
    public private(set) var selection: PickerSelection? = nil

    /// The strip's targets, numbered 1–9 straight across the groups.
    public var pinned: [Target] { strip.flatMap { $0 } }
    /// ⋯ is disabled when there is nothing under it.
    public var moreIsEnabled: Bool { more.contains { !$0.isEmpty } }

    /// Selects the preselection: its tile when pinned, ⋯ when it is in the menu, else the first
    /// tile (or ⋯ when nothing is pinned).
    public init(link: IncomingLink, strip: [[Target]], more: [[Target]], preselected: Target.ID?) {
        self.link = link
        self.strip = strip
        self.more = more
        let pinned = strip.flatMap { $0 }
        let inMore = more.joined().contains { $0.id == preselected }
        moreHighlight = inMore ? preselected : nil
        if let preselected, pinned.contains(where: { $0.id == preselected }) {
            selection = .target(preselected)
        } else if inMore {
            selection = .more
        } else if let first = pinned.first {
            selection = .target(first.id)
        } else if moreIsEnabled {
            selection = .more
        }
    }

    /// Positions the arrows move through.
    private var positions: [PickerSelection] {
        pinned.map { .target($0.id) } + (moreIsEnabled ? [.more] : [])
    }

    /// The step a key leads to; nil when it only moves the selection or does nothing.
    public mutating func handle(_ key: PickerKey) -> PickerStep? {
        switch key {
        case .digit(let n):
            guard pinned.indices.contains(n - 1) else { return nil }
            return .finish(.open(pinned[n - 1].id, always: false))
        case .more:
            return moreIsEnabled ? .showMore(highlighted: moreHighlight) : nil
        case .enter, .optionEnter:
            switch selection {
            case .target(let id): return .finish(.open(id, always: key == .optionEnter))
            case .more: return .showMore(highlighted: moreHighlight)
            case nil: return nil
            }
        case .copy:
            return .finish(.copy(TrackingParameters.stripped(link.url)))
        case .escape:
            return .finish(.cancel)
        case .left, .right:
            guard let index = positions.firstIndex(where: { $0 == selection }) else { return nil }
            let moved = key == .left ? max(index - 1, 0) : min(index + 1, positions.count - 1)
            selection = positions[moved]
            return nil
        }
    }
}
