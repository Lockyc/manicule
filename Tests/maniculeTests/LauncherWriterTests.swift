import XCTest
import ManiculeCore
@testable import manicule

final class LauncherWriterTests: XCTestCase {
    private var home: URL!
    private let docsID = WebApp.docs.chromeAppID

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("launcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: home) }

    private func spec(_ name: String) -> LauncherSpec {
        LauncherSpec(appName: name, bundleID: "com.lockyc.manicule.launcher.docs.P", chromeAppID: docsID,
                     command: LaunchCommand(executable: "/usr/bin/open", arguments: ["-na", "Google Chrome"]))
    }

    private func addShim(withIcon: Bool) throws {
        let shim = home.appendingPathComponent("Applications/Chrome Apps.localized/Google Docs.app/Contents")
        try FileManager.default.createDirectory(at: shim.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        try XCTUnwrap(NSDictionary(dictionary: ["CrAppModeShortcutID": docsID]).write(to: shim.appendingPathComponent("Info.plist"), atomically: true) ? () : nil)
        if withIcon { try Data("icns".utf8).write(to: shim.appendingPathComponent("Resources/app.icns")) }
    }

    func testWritesBundleWithExecutableScriptAndPlist() throws {
        let writer = LauncherWriter(home: home)
        _ = writer.write([spec("Docs – LSJC")])
        let app = writer.folder.appendingPathComponent("Docs – LSJC.app/Contents")
        let script = app.appendingPathComponent("MacOS/launch")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: script.path))
        XCTAssertEqual(try String(contentsOf: script, encoding: .utf8), "#!/bin/sh\nexec '/usr/bin/open' '-na' 'Google Chrome'\n")
        let plist = try XCTUnwrap(NSDictionary(contentsOf: app.appendingPathComponent("Info.plist")))
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "launch")
        XCTAssertEqual(plist["CFBundleName"] as? String, "Docs – LSJC")
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
        XCTAssertNil(plist["CFBundleIconFile"])
    }

    func testCopiesIconFromChromeShimAndLeavesShimsAlone() throws {
        try addShim(withIcon: true)
        let writer = LauncherWriter(home: home)
        _ = writer.write([spec("Docs – LSJC")])
        let app = writer.folder.appendingPathComponent("Docs – LSJC.app/Contents")
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("Resources/app.icns").path))
        let plist = try XCTUnwrap(NSDictionary(contentsOf: app.appendingPathComponent("Info.plist")))
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "app")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: writer.chromeApps.path), ["Google Docs.app"])
    }

    func testRemovesStaleLauncherAppsOnly() throws {
        let writer = LauncherWriter(home: home)
        _ = writer.write([spec("Docs – A"), spec("Docs – B")])
        try Data().write(to: writer.folder.appendingPathComponent("keep.txt"))
        _ = writer.write([spec("Docs – B")])
        let left = try FileManager.default.contentsOfDirectory(atPath: writer.folder.path).sorted()
        XCTAssertEqual(left, ["Docs – B.app", "keep.txt"])
    }

    func testSeparatorsInNameStayInsideFolder() throws {
        let writer = LauncherWriter(home: home)
        let failures = writer.write([spec("Docs – x/../../y"), spec("Docs – Work/Home")])
        XCTAssertTrue(failures.isEmpty)
        let left = try FileManager.default.contentsOfDirectory(atPath: writer.folder.path).sorted()
        XCTAssertEqual(left, ["Docs – Work-Home.app", "Docs – x-..-..-y.app"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent("Applications").path).sorted(),
                       ["Manicule Launchers"])
    }

    func testUnchangedBundleIsNotRewritten() throws {
        let writer = LauncherWriter(home: home)
        _ = writer.write([spec("Docs – LSJC")])
        let plist = writer.folder.appendingPathComponent("Docs – LSJC.app/Contents/Info.plist")
        let past = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: plist.path)
        XCTAssertTrue(writer.write([spec("Docs – LSJC")]).isEmpty)
        let after = try FileManager.default.attributesOfItem(atPath: plist.path)[.modificationDate] as? Date
        XCTAssertEqual(after, past)
    }

    func testFailedSigningRemovesBundleAndNextWriteRebuilds() throws {
        var writer = LauncherWriter(home: home)
        writer.signer = URL(fileURLWithPath: "/usr/bin/false")
        let failures = writer.write([spec("Docs – LSJC")])
        XCTAssertEqual(failures.count, 1)
        let bundle = writer.folder.appendingPathComponent("Docs – LSJC.app")
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundle.path))
        writer.signer = URL(fileURLWithPath: "/usr/bin/codesign")
        XCTAssertTrue(writer.write([spec("Docs – LSJC")]).isEmpty)
        let verify = Process()
        verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verify.arguments = ["--verify", bundle.path]
        try verify.run()
        verify.waitUntilExit()
        XCTAssertEqual(verify.terminationStatus, 0)
    }
}
