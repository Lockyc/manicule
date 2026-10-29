import Foundation

/// What the user did in the picker.
public enum PickerAction: Equatable, Sendable {
    case open(Target.ID, always: Bool)
    case copy(URL)
    case cancel
}

/// The picker UI. Calls `completion` exactly once, on the main thread.
public protocol Picking: AnyObject {
    func show(_ link: IncomingLink, targets: [Target], preselected: Target.ID?,
              completion: @escaping (PickerAction) -> Void)
}
