import AppKit
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
    @ObservationIgnored private var reloading = false

    /// Every change is saved; launchers are rewritten only when targets or visibility change
    /// (a history write never runs codesign), and by `reload` after a discovery.
    var config = Config(targets: [], visible: []) {
        didSet {
            guard config != oldValue else { return }
            save()
            if !reloading, config.targets != oldValue.targets || config.visible != oldValue.visible {
                refreshLaunchers()
            }
        }
    }
    /// The latest discovery; carries each profile's installed web apps, which the config doesn't store.
    private(set) var discovered: [DiscoveredProfile] = []
    /// Installed browsers whose profile file macOS won't let Manicule read yet.
    private(set) var unreadable: [BrowserRoot] = []
    /// Browsers with an app on this Mac.
    private(set) var installed: Set<Browser> = []
    /// Why changes can't be saved (the config file couldn't be taken in safely); nil when they can.
    private(set) var saveRefusal: String?

    @ObservationIgnored private let isInstalled: (Browser) -> Bool

    init(store: ConfigStore, home: URL = FileManager.default.homeDirectoryForCurrentUser,
         isInstalled: @escaping (Browser) -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }) {
        self.store = store
        self.home = home
        self.isInstalled = isInstalled
        self.launchers = LauncherWriter(home: home)
        reload()
    }

    /// Re-reads installed browser profiles and the saved config and merges profiles found since
    /// (`config`'s didSet saves the result). Run at launch, when Settings opens, and after a
    /// folder-access grant.
    func reload() {
        installed = Set(Browser.allCases.filter(isInstalled))
        discovered = ProfileDiscovery.discoverAll(home: home, installed: installed)
        unreadable = ProfileDiscovery.unreadableRoots(home: home)
        var loaded = store.load(discovered: discovered)
        saveRefusal = store.saveRefusal
        loaded.merge(discovered: discovered)
        reloading = true
        config = loaded
        reloading = false
        refreshLaunchers()
    }

    func target(_ id: Target.ID) -> Target? {
        config.targets.first { $0.id == id }
    }

    /// Targets that can open on this Mac now; the rest show as not found and never route.
    var available: Set<Target.ID> {
        config.available(discovered: discovered, unreadable: unreadable.map(\.browser))
    }

    /// Read fresh on every call: flotilla's groups come from its manifest, which it rewrites
    /// whenever its windows change, so each routing sees the groups open now.
    var routerState: RouterState {
        config.routerState(available: available,
                           flotillaGroups: Flotilla.groupTargets(Flotilla.load(from: Flotilla.manifest(home: home))))
    }

    /// What Settings calls a target a rule or remembered document names: a gone flotilla group by
    /// its "(closed)" name, a stored target by its own even when it isn't on this Mac.
    func targetName(_ id: Target.ID) -> String {
        routerState.target(id)?.name ?? target(id)?.name ?? "Missing target (\(id))"
    }

    /// Settings → Targets' sections: browsers installed, unreadable or with targets, in browser order.
    var browserSections: [Browser] {
        config.browserSections(including: installed.union(unreadable.map(\.browser)))
    }

    static let veljaPreferences = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/com.sindresorhus.Velja/Data/Library/Preferences/com.sindresorhus.Velja.plist")

    static var veljaInstalled: Bool { FileManager.default.fileExists(atPath: veljaPreferences.path) }

    /// Appends Velja's mappable rules and returns the line to show the user.
    func importVeljaRules() -> String {
        guard let data = try? Data(contentsOf: Self.veljaPreferences) else { return "Velja's preferences can't be read" }
        let result = VeljaImport.result(fromPreferences: data, targets: config.targets, existing: config.rules,
                                        defaultTargets: Set(discovered.filter(\.isDefault).map(\.targetID)))
        config.rules.append(contentsOf: result.rules)
        var parts: [String] = []
        if !result.rules.isEmpty { parts.append("Imported \(result.rules.count) rule\(result.rules.count == 1 ? "" : "s")") }
        if result.skipped > 0 { parts.append("Skipped \(result.skipped) that Manicule can't map") }
        return parts.isEmpty ? "No rules to import" : parts.joined(separator: ". ")
    }

    private func save() {
        do { try store.save(config) } catch {
            Self.log.error("config save failed: \(String(describing: error), privacy: .public)")
        }
    }
}

extension AppModel {
    /// Rewrites the per-profile web-app launchers when the set they derive from has changed. Runs
    /// on the main thread; it is called only on target, visibility or discovery changes, and an
    /// unchanged bundle is never re-signed. Launchers of a browser that can't be read yet are kept.
    private func refreshLaunchers() {
        let shown = Set(config.visible)
        let specs = LauncherSpecs.make(visible: config.targets.filter { shown.contains($0.id) }, profiles: discovered)
        guard specs != writtenLaunchers else { return }
        let failures = launchers.write(specs, keeping: Set(unreadable.map(\.browser)))
        for failure in failures {
            Self.log.error("launcher write failed: \(failure.description, privacy: .public)")
        }
        if failures.isEmpty { writtenLaunchers = specs }
    }
}
