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

    /// The line beside the toggle, when there is something to say. `.notFound` is also what an app
    /// that has never registered reports, so it reads as off rather than unavailable.
    static func note(_ status: SMAppService.Status) -> String? {
        status == .requiresApproval ? "Waiting for approval in System Settings → Login Items" : nil
    }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
