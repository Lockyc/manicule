import Foundation
import ManiculeCore

/// Writes one tiny `.app` per `LauncherSpec` into `folder` so Spotlight and the Dock can open a
/// Chrome web app in a specific profile. Only `folder` is ever written; `chromeApps` is read for icons.
struct LauncherWriter {
    var folder: URL
    var chromeApps: URL
    var signer = URL(fileURLWithPath: "/usr/bin/codesign")

    init(home: URL) {
        folder = home.appendingPathComponent("Applications/Manicule Launchers")
        chromeApps = home.appendingPathComponent("Applications/Chrome Apps.localized")
    }

    struct Failure: Error, CustomStringConvertible {
        var app: String
        var reason: String
        var description: String { "\(app): \(reason)" }
    }

    /// Brings `folder` in line with `specs`; returns what could not be written. A bundle already
    /// on disk exactly as it would be written is left untouched.
    func write(_ specs: [LauncherSpec]) -> [Failure] {
        let fm = FileManager.default
        var failures: [Failure] = []
        do { try fm.createDirectory(at: folder, withIntermediateDirectories: true) } catch {
            return [Failure(app: folder.lastPathComponent, reason: error.localizedDescription)]
        }
        let wanted = Set(specs.map { Self.fileName($0.appName) })
        for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        where name.hasSuffix(".app") && !wanted.contains(name) {
            do { try fm.removeItem(at: folder.appendingPathComponent(name)) } catch {
                failures.append(Failure(app: name, reason: error.localizedDescription))
            }
        }
        for spec in specs {
            do { try writeBundle(spec) } catch {
                failures.append(Failure(app: spec.appName, reason: "\(error)"))
            }
        }
        return failures
    }

    /// The launcher's file name: path separators in a profile name never reach the file system.
    static func fileName(_ appName: String) -> String {
        appName.map { $0 == "/" || $0 == ":" ? "-" : $0 }.reduce("") { $0 + String($1) } + ".app"
    }

    private func writeBundle(_ spec: LauncherSpec) throws {
        let fm = FileManager.default
        let bundle = folder.appendingPathComponent(Self.fileName(spec.appName))
        guard bundle.standardizedFileURL.deletingLastPathComponent().path == folder.standardizedFileURL.path else {
            throw Failure(app: spec.appName, reason: "path escapes the launchers folder")
        }
        let icon = iconURL(chromeAppID: spec.chromeAppID)

        var plist: [String: Any] = [
            "CFBundleIdentifier": spec.bundleID,
            "CFBundleExecutable": "launch",
            "CFBundleName": spec.appName,
            "CFBundlePackageType": "APPL",
            "LSUIElement": true,
        ]
        if icon != nil { plist["CFBundleIconFile"] = "app" }
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let scriptData = Data(LauncherSpecs.script(for: spec.command).utf8)

        let plistURL = bundle.appendingPathComponent("Contents/Info.plist")
        let scriptURL = bundle.appendingPathComponent("Contents/MacOS/launch")
        let iconDest = bundle.appendingPathComponent("Contents/Resources/app.icns")
        if (try? Data(contentsOf: plistURL)) == plistData,
           (try? Data(contentsOf: scriptURL)) == scriptData,
           fm.fileExists(atPath: iconDest.path) == (icon != nil),
           fm.isExecutableFile(atPath: scriptURL.path) {
            return
        }

        try? fm.removeItem(at: bundle)
        try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let icon {
            try fm.createDirectory(at: iconDest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: icon, to: iconDest)
        }
        try plistData.write(to: plistURL)
        try scriptData.write(to: scriptURL)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let sign = Process()
        sign.executableURL = signer
        sign.arguments = ["--force", "--sign", "-", bundle.path]
        sign.standardOutput = FileHandle.nullDevice
        sign.standardError = FileHandle.nullDevice
        do { try sign.run() } catch {
            try? fm.removeItem(at: bundle)
            throw error
        }
        sign.waitUntilExit()
        guard sign.terminationStatus == 0 else {
            try? fm.removeItem(at: bundle)  // an unsigned bundle must not pass the skip check next time
            throw Failure(app: spec.appName, reason: "codesign exited \(sign.terminationStatus)")
        }
    }

    /// Chrome's own shim for the app: the bundle whose `CrAppModeShortcutID` is the app id.
    private func iconURL(chromeAppID: String) -> URL? {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: chromeApps.path)) ?? [] where name.hasSuffix(".app") {
            let shim = chromeApps.appendingPathComponent(name)
            let info = NSDictionary(contentsOf: shim.appendingPathComponent("Contents/Info.plist"))
            guard info?["CrAppModeShortcutID"] as? String == chromeAppID else { continue }
            let icns = shim.appendingPathComponent("Contents/Resources/app.icns")
            if fm.fileExists(atPath: icns.path) { return icns }
        }
        return nil
    }
}
