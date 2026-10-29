import Foundation
import ManiculeCore
import Observation
import os

/// The one owner of the running config. Routing and Settings both edit `config` here, and every
/// change is saved.
@MainActor @Observable
final class AppModel {
    @ObservationIgnored private static let log = Logger(subsystem: "com.lockyc.manicule", category: "config")
    @ObservationIgnored private let store: ConfigStore
    @ObservationIgnored private let home: URL
    @ObservationIgnored private let launchers: LauncherWriter
    @ObservationIgnored private var writtenLaunchers: [LauncherSpec]?

    var config = Config(targets: [], visible: []) {
        didSet { if config != oldValue { save(); refreshLaunchers() } }
    }
    /// The latest discovery; carries each profile's installed web apps, which the config doesn't store.
    private(set) var discovered: [DiscoveredProfile] = []
    /// Installed browsers whose profile file macOS won't let Manicule read yet.
    private(set) var unreadable: [BrowserRoot] = []

    init(store: ConfigStore, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.store = store
        self.home = home
        self.launchers = LauncherWriter(home: home)
        reload()
    }

    /// Re-reads installed browser profiles and the saved config and merges profiles found since
    /// (`config`'s didSet saves the result). Run at launch, when Settings opens, and after a
    /// folder-access grant.
    func reload() {
        discovered = ProfileDiscovery.discoverAll(home: home)
        unreadable = ProfileDiscovery.unreadableRoots(home: home)
        var loaded = store.load(discovered: discovered)
        loaded.merge(discovered: discovered)
        config = loaded
        refreshLaunchers()
    }

    func target(_ id: Target.ID) -> Target? {
        config.targets.first { $0.id == id }
    }

    static let veljaPreferences = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/com.sindresorhus.Velja/Data/Library/Preferences/com.sindresorhus.Velja.plist")

    static var veljaInstalled: Bool { FileManager.default.fileExists(atPath: veljaPreferences.path) }

    /// Appends Velja's mappable rules and returns the line to show the user.
    func importVeljaRules() -> String {
        guard let data = try? Data(contentsOf: Self.veljaPreferences) else { return "Velja's preferences can't be read" }
        let result = VeljaImport.result(fromPreferences: data, targets: config.targets, existing: config.rules)
        config.rules.append(contentsOf: result.rules)
        var parts: [String] = []
        if !result.rules.isEmpty { parts.append("Imported \(result.rules.count) rule\(result.rules.count == 1 ? "" : "s")") }
        if result.skipped > 0 { parts.append("Skipped \(result.skipped) that Manicule can't map") }
        return parts.isEmpty ? "No rules to import" : parts.joined(separator: ". ")
    }

    private func save() {
        do { try store.save(config) } catch {
            Self.log.error("config save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension AppModel {
    /// Rewrites the per-profile web-app launchers when the set they derive from has changed.
    private func refreshLaunchers() {
        let shown = Set(config.visible)
        let specs = LauncherSpecs.make(visible: config.targets.filter { shown.contains($0.id) }, profiles: discovered)
        guard specs != writtenLaunchers else { return }
        let failures = launchers.write(specs)
        for failure in failures {
            Self.log.error("launcher write failed: \(failure.description, privacy: .public)")
        }
        if failures.isEmpty { writtenLaunchers = specs }
    }
}
