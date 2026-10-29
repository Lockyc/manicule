import Foundation
import ManiculeCore

final class Launcher {
    /// Starts the command without waiting for it; the browser outlives us.
    func run(_ command: LaunchCommand) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        try process.run()
    }
}
