import AppKit
import ManiculeCore
import os

final class Launcher {
    private static let log = Logger(subsystem: "com.lockyc.manicule", category: "launch")

    enum Mode: Equatable {
        /// Run the command as a child process.
        case process
        /// Open the app bundle through Launch Services with the command's arguments.
        case openApplication(URL)
    }

    /// Firefox's binary hands a URL to the running instance of its profile; when Firefox isn't
    /// running, that binary would become Manicule's child, so Launch Services starts it instead.
    static func mode(for command: LaunchCommand, firefoxRunning: Bool) -> Mode {
        let inBundle = "/Contents/MacOS/firefox"
        guard command.executable.hasSuffix(".app" + inBundle), !firefoxRunning else { return .process }
        return .openApplication(URL(fileURLWithPath: String(command.executable.dropLast(inBundle.count))))
    }

    /// Starts the command without waiting for it; the browser outlives us.
    func run(_ command: LaunchCommand) throws {
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: Browser.firefox.bundleID).isEmpty
        switch Self.mode(for: command, firefoxRunning: running) {
        case .process:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
            try process.run()
        case .openApplication(let app):
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = command.arguments
            NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
                if let error {
                    Self.log.error("opening \(app.lastPathComponent, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
