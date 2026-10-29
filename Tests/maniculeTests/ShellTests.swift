import XCTest
import ManiculeCore
@testable import manicule

final class ShellTests: XCTestCase {
    func testShellSeesCoreAcrossModuleBoundary() {
        XCTAssertEqual(Manicule.name, "manicule")
    }
}

final class LauncherTests: XCTestCase {
    private let firefox = LaunchCommand(executable: "/Apps/Firefox.app/Contents/MacOS/firefox",
                                        arguments: ["--profile", "/p", "--new-tab", "https://example.com"])

    /// A cold Firefox started as Manicule's child would die with it; Launch Services owns it instead.
    func testColdFirefoxOpensThroughLaunchServices() {
        XCTAssertEqual(Launcher.mode(for: firefox, firefoxRunning: false),
                       .openApplication(URL(fileURLWithPath: "/Apps/Firefox.app")))
    }

    func testRunningFirefoxTakesTheBinaryHandOff() {
        XCTAssertEqual(Launcher.mode(for: firefox, firefoxRunning: true), .process)
    }

    func testOtherBrowsersRunTheCommand() {
        let chrome = LaunchCommand(executable: "/usr/bin/open", arguments: ["-na", "Google Chrome", "--args"])
        XCTAssertEqual(Launcher.mode(for: chrome, firefoxRunning: false), .process)
    }
}
