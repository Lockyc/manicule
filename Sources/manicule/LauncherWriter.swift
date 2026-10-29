import Foundation
import ManiculeCore

/// Writes one tiny `.app` per `LauncherSpec` into `folder` so Spotlight and the Dock can open a
/// Chrome web app in a specific profile. Only `folder` is ever written; `chromeApps` is read for icons.
struct LauncherWriter {
    var folder: URL
    var chromeApps: URL

    init(home: URL) {
        folder = home.appendingPathComponent("Applications/Manicule Launchers")
        chromeApps = home.appendingPathComponent("Applications/Chrome Apps.localized")
    }

    func write(_ specs: [LauncherSpec]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let wanted = Set(specs.map { $0.appName + ".app" })
        let existing = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in existing where name.hasSuffix(".app") && !wanted.contains(name) {
            try? fm.removeItem(at: folder.appendingPathComponent(name))
        }
        for spec in specs { try? writeBundle(spec) }
    }

    private func writeBundle(_ spec: LauncherSpec) throws {
        let fm = FileManager.default
        let bundle = folder.appendingPathComponent(spec.appName + ".app")
        try? fm.removeItem(at: bundle)
        let macOS = bundle.appendingPathComponent("Contents/MacOS")
        let resources = bundle.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)

        var hasIcon = false
        if let icon = iconURL(chromeAppID: spec.chromeAppID) {
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)
            hasIcon = (try? fm.copyItem(at: icon, to: resources.appendingPathComponent("app.icns"))) != nil
        }

        var plist: [String: Any] = [
            "CFBundleIdentifier": spec.bundleID,
            "CFBundleExecutable": "launch",
            "CFBundleName": spec.appName,
            "CFBundlePackageType": "APPL",
            "LSUIElement": true,
        ]
        if hasIcon { plist["CFBundleIconFile"] = "app" }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: bundle.appendingPathComponent("Contents/Info.plist"))

        let script = macOS.appendingPathComponent("launch")
        try LauncherSpecs.script(for: spec.command).write(to: script, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", "-", bundle.path]
        sign.standardOutput = FileHandle.nullDevice
        sign.standardError = FileHandle.nullDevice
        try sign.run()
        sign.waitUntilExit()
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
