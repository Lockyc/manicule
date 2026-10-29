import Foundation

/// A key the picker understands, already decoded from the raw event by the shell.
public enum PickerKey: Equatable, Sendable {
    /// 1-based position in the strip.
    case digit(Int)
    case enter, optionEnter, copy, escape, left, right
}

/// The picker's state and key handling, independent of any window.
public struct PickerModel: Sendable {
    public let link: IncomingLink
    public let targets: [Target]
    /// The highlighted target: the preselection when it is in the strip, else the first.
    public private(set) var selection: Target.ID?

    public init(link: IncomingLink, targets: [Target], preselected: Target.ID?) {
        self.link = link
        self.targets = targets
        selection = targets.contains { $0.id == preselected } ? preselected : targets.first?.id
    }

    /// The action a key completes the picker with; nil when it only moves the selection or does nothing.
    public mutating func handle(_ key: PickerKey) -> PickerAction? {
        switch key {
        case .digit(let n):
            guard targets.indices.contains(n - 1) else { return nil }
            return .open(targets[n - 1].id, always: false)
        case .enter:
            return selection.map { .open($0, always: false) }
        case .optionEnter:
            return selection.map { .open($0, always: true) }
        case .copy:
            return .copy(TrackingParameters.stripped(link.url))
        case .escape:
            return .cancel
        case .left, .right:
            guard let index = targets.firstIndex(where: { $0.id == selection }) else { return nil }
            let moved = key == .left ? max(index - 1, 0) : min(index + 1, targets.count - 1)
            selection = targets[moved].id
            return nil
        }
    }
}
