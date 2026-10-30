import AppKit
import ManiculeCore
import SwiftUI
import XCTest
@testable import manicule

/// Settings and the model behind it, built off-screen against a temp home and config directory.
@MainActor
final class SettingsTests: XCTestCase {
    private var home: URL!
    private var dir: URL!
    private var lockedFiles: [URL] = []

    override func setUpWithError() throws {
        _ = NSApplication.shared
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("manicule-settings-\(UUID().uuidString)")
        home = base.appendingPathComponent("home")
        dir = base.appendingPathComponent("config")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
    }

    override func tearDown() {
        for file in lockedFiles {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        }
    }

    private let localState = #"{"profile":{"info_cache":{"Default":{"name":"Work","user_name":"a@example.com"}}}}"#

    private func seededModel(installed: Set<Browser> = [.safari]) throws -> AppModel {
        var config = Config.defaults(from: ProfileDiscovery.discoverAll(home: home, installed: []))
        config.rules = [Rule(title: "Example", matchers: [.hostSuffix("example.com")], target: "safari|")]
        config.rememberedDocuments = ["abc123": "safari|"]
        let seeding = ConfigStore(directory: dir)
        _ = seeding.load(discovered: [])
        try seeding.save(config)
        return AppModel(store: ConfigStore(directory: dir), home: home, isInstalled: installed.contains)
    }

    private func writeFlotillaManifest(groups: [String]) throws {
        let file = Flotilla.manifest(home: home)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let list = groups.map { "\"\($0)\"" }.joined(separator: ",")
        try ##"{"version":1,"windows":[{"title":"Rotary","colour":"#17458f","groups":[\##(list)]}]}"##
            .write(to: file, atomically: true, encoding: .utf8)
    }

    /// The rule picker offers flotilla's live groups, read from its manifest on every routing; a
    /// rule or remembered document naming a gone group shows that group's "(closed)" name.
    func testRulePickerOffersGroupsAndNamesGoneOnes() throws {
        try writeFlotillaManifest(groups: ["Bulletins"])
        let model = try seededModel(installed: [.safari, .flotilla])
        XCTAssertEqual(RulesTab.choices(model).filter { $0.browser == .flotilla }.map(\.name),
                       ["flotilla", "flotilla · Rotary", "flotilla · Rotary ▸ Bulletins"])

        try writeFlotillaManifest(groups: ["Bulletins", "Minutes"])
        XCTAssertTrue(RulesTab.choices(model).contains { $0.id == "flotilla|Rotary|Minutes" }, "read per routing, no reload")

        let gone = Flotilla.groupID(window: "Rotary", group: "Agenda")
        XCTAssertEqual(model.targetName(gone), "flotilla · Rotary ▸ Agenda (closed)")
        XCTAssertEqual(model.targetName("safari|"), "Safari")
        XCTAssertEqual(model.targetName("chrome|Profile 9"), "Missing target (chrome|Profile 9)")
        model.config.rules[0].target = gone
        model.config.rememberedDocuments["abc123"] = gone
        for view in [AnyView(RulesTab(model: model)), AnyView(DocumentsTab(model: model))] {
            let hosting = NSHostingView(rootView: AnyView(view.frame(width: 700, height: 480)))
            hosting.frame = NSRect(x: 0, y: 0, width: 700, height: 480)
            hosting.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(hosting.fittingSize.height, 0)
        }
    }

    /// Launchers are rewritten only when targets, visibility or discovery change — a history
    /// write never re-runs codesign, even after an earlier write failed.
    func testHistoryWritesDoNotRegenerateLaunchers() throws {
        let chrome = home.appendingPathComponent("Library/Application Support/Google/Chrome")
        try FileManager.default.createDirectory(
            at: chrome.appendingPathComponent("Default/Web Applications/Manifest Resources/\(WebApp.docs.chromeAppID)"),
            withIntermediateDirectories: true)
        try localState.write(to: chrome.appendingPathComponent("Local State"), atomically: true, encoding: .utf8)
        let folder = home.appendingPathComponent("Applications/Manicule Launchers")
        try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: folder)  // a file where the folder goes: the first write fails

        let model = try seededModel()
        try FileManager.default.removeItem(at: folder)
        model.config.recordOutcome(IncomingLink(url: URL(string: "https://example.com")!, sourceApp: nil,
                                                receivedAt: Date()), target: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))

        model.config.setVisible("chrome|Default", false)
        model.config.setVisible("chrome|Default", true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Docs – Work.app").path))
    }

    func testUnsavableConfigIsReportedAndLeftAlone() throws {
        _ = try seededModel()
        let file = dir.appendingPathComponent("config.json")
        let before = try Data(contentsOf: file)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        lockedFiles.append(file)
        let model = AppModel(store: ConfigStore(directory: dir), home: home, isInstalled: { $0 == .safari })
        model.config.rules = []
        let problem = try XCTUnwrap(GeneralTab.saveProblem(model.saveRefusal))
        XCTAssertTrue(problem.hasPrefix("Settings can't be saved: "), problem)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertNil(GeneralTab.saveProblem(nil))
    }

    func testLoginItemToggleFollowsMacOSState() {
        XCTAssertTrue(LoginItem.isOn(.enabled))
        XCTAssertTrue(LoginItem.isOn(.requiresApproval), "registered, awaiting approval")
        XCTAssertFalse(LoginItem.isOn(.notRegistered))
        XCTAssertFalse(LoginItem.isOn(.notFound), "never registered")
        XCTAssertNotNil(LoginItem.note(.requiresApproval))
        XCTAssertNil(LoginItem.note(.notFound))
        XCTAssertNil(LoginItem.note(.enabled))
        XCTAssertNil(LoginItem.note(.notRegistered))
    }

    private func savedConfig() throws -> Config {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Config.self, from: Data(contentsOf: dir.appendingPathComponent("config.json")))
    }

    func testEveryEditIsSaved() throws {
        let model = try seededModel()
        model.config.rules[0].title = "Edited"
        model.config.rules[0].matchers.append(Matcher(kind: .pathContains, value: "/u/1/"))
        XCTAssertEqual(try savedConfig().rules[0].title, "Edited")
        XCTAssertEqual(try savedConfig().rules[0].matchers, [.hostSuffix("example.com"), .pathContains("/u/1/")])
        model.config.rememberedDocuments.removeAll()
        XCTAssertEqual(try savedConfig().rememberedDocuments, [:])
    }

    func testUnreadableBrowserListedUntilReadableThenMergedHidden() throws {
        let chrome = home.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
        try FileManager.default.createDirectory(at: chrome, withIntermediateDirectories: true)
        let file = chrome.appendingPathComponent("Local State")
        try localState.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        lockedFiles.append(file)

        let model = try seededModel()
        XCTAssertEqual(model.unreadable.map(\.browser), [.chrome])
        XCTAssertEqual(model.config.targets.map(\.id), ["safari|"])

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        model.reload()
        XCTAssertEqual(model.unreadable, [])
        XCTAssertEqual(model.config.targets.map(\.id), ["safari|", "chrome|Default"])
        XCTAssertEqual(model.config.visible, ["safari|"], "found later, so hidden")
        XCTAssertEqual(try savedConfig().targets.map(\.id), ["safari|", "chrome|Default"])
    }

    /// An unreadable browser is a Targets section of its own, with the grant in place.
    func testTargetsAreSectionedByBrowserIncludingUnreadableOnes() throws {
        let chrome = home.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
        try FileManager.default.createDirectory(at: chrome, withIntermediateDirectories: true)
        let file = chrome.appendingPathComponent("Local State")
        try localState.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        lockedFiles.append(file)

        let model = try seededModel()
        XCTAssertTrue(model.browserSections.contains(.chrome))
        XCTAssertTrue(model.browserSections.contains(.safari))
        XCTAssertEqual(BrowserAccessRow.label(.chrome), "Can't read Chrome's profiles yet")
        let order = model.config.browserOrder
        XCTAssertEqual(model.browserSections, order.filter(model.browserSections.contains), "in browser order")
    }

    func testBrowserOrderIsSaved() throws {
        let model = try seededModel()
        model.config.moveBrowser(.safari, to: model.config.browserOrder[0])
        XCTAssertEqual(try savedConfig().browserOrder.first, .safari)
    }

    func testGrantPanelOpensAtTheBrowserFolder() {
        let folder = home.appendingPathComponent("Library/Application Support/Firefox", isDirectory: true)
        let panel = BrowserAccess.panel(for: BrowserRoot(browser: .firefox, folder: folder,
                                                         profileFile: folder.appendingPathComponent("profiles.ini")))
        XCTAssertEqual(panel.directoryURL?.standardizedFileURL.path, folder.standardizedFileURL.path)
        XCTAssertTrue(panel.canChooseDirectories)
        XCTAssertFalse(panel.canChooseFiles)
        XCTAssertEqual(panel.message, "Click Open to let Manicule read your Firefox profiles.")
    }

    func testSettingsWindowBuildsOffScreen() throws {
        let controller = SettingsWindowController(model: try seededModel())
        let window = controller.window
        XCTAssertTrue(window.contentViewController is NSHostingController<SettingsView>)
        XCTAssertFalse(window.isVisible)
        window.layoutIfNeeded()
        XCTAssertGreaterThanOrEqual(window.contentLayoutRect.width, 680)
        XCTAssertTrue(window.styleMask.contains(.closable))
        window.close()
    }

    /// TabView only builds the selected tab, so each tab is hosted on its own, with data and empty.
    func testEveryTabLaysOut() throws {
        let model = try seededModel()
        func host(_ view: some View) -> NSHostingView<AnyView> {
            let hosting = NSHostingView(rootView: AnyView(view.frame(width: 700, height: 480)))
            hosting.frame = NSRect(x: 0, y: 0, width: 700, height: 480)
            hosting.layoutSubtreeIfNeeded()
            return hosting
        }
        for _ in 0..<2 {
            for view in [AnyView(TargetsTab(model: model)), AnyView(RulesTab(model: model)),
                         AnyView(DocumentsTab(model: model)), AnyView(GeneralTab(model: model))] {
                XCTAssertGreaterThan(host(view).fittingSize.height, 0)
            }
            model.config.rules = []
            model.config.rememberedDocuments = [:]
        }
    }

    /// The section heading names the browser, so the row doesn't.
    func testTargetDetailNamesAccountAndFolder() {
        let target = Target(id: "chrome|Profile 3", browser: .chrome, profile: "Profile 3", name: "Work", email: "a@example.com")
        XCTAssertEqual(TargetsTab.detail(target, found: true), "a@example.com · Folder: Profile 3")
        let safari = Target(id: "safari|", browser: .safari, profile: nil, name: "Safari", email: nil)
        XCTAssertEqual(TargetsTab.detail(safari, found: true), "No account")
        XCTAssertEqual(TargetsTab.detail(target, found: false),
                       "a@example.com · Folder: Profile 3 · Not found on this Mac")
    }

    func testTargetMissingFromThisMacStaysListedButLeavesThePicker() throws {
        let model = try seededModel()
        model.config.targets.append(Target(id: "chrome|Profile 9", browser: .chrome, profile: "Profile 9",
                                           name: "Gone", email: nil))
        model.config.setVisible("chrome|Profile 9", true)
        XCTAssertFalse(model.available.contains("chrome|Profile 9"))
        XCTAssertTrue(model.config.targets.contains { $0.id == "chrome|Profile 9" })
        XCTAssertFalse(model.routerState.pickerTargets.contains { $0.id == "chrome|Profile 9" })
    }
}
