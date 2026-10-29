import Foundation

/// Links awaiting the picker, one shown at a time; none is dropped while another is showing.
public struct LinkQueue: Sendable {
    private var pending: [IncomingLink] = []
    public private(set) var current: IncomingLink?

    public init() {}

    /// True when the link is now `current` and should be shown; false when it waits behind one already showing.
    public mutating func enqueue(_ link: IncomingLink) -> Bool {
        if current == nil {
            current = link
            return true
        }
        pending.append(link)
        return false
    }

    /// Retires the current link and returns the next to show, nil when none remain.
    public mutating func resolveCurrent() -> IncomingLink? {
        current = pending.isEmpty ? nil : pending.removeFirst()
        return current
    }
}
