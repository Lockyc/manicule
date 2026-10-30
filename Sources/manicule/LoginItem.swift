import ServiceManagement

/// Opening Manicule at login, via the app's own login item. macOS holds the state (System
/// Settings → Login Items), so it is read back from there, never stored in the config.
@MainActor
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    /// Whether the toggle shows on: registered, including while it waits for the user's approval.
    static func isOn(_ status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }

    /// Whether the toggle can act: macOS finds no login item for an app run outside its bundle.
    static func isAvailable(_ status: SMAppService.Status) -> Bool { status != .notFound }

    /// The line beside the toggle, when there is something to say.
    static func note(_ status: SMAppService.Status) -> String? {
        switch status {
        case .requiresApproval: "Waiting for approval in System Settings → Login Items"
        case .notFound: "Available when Manicule runs from /Applications"
        default: nil
        }
    }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
