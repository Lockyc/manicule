import AppKit
import ManiculeCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "com.lockyc.manicule", category: "app")

    private let model: AppModel
    private let launcher = Launcher()
    private let picker = PickerPanel()
    private var queue = LinkQueue()
    private var statusItem: StatusItemController?
    private var settings: SettingsWindowController?

    override init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        model = AppModel(store: ConfigStore(directory: support.appendingPathComponent("Manicule")))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        statusItem = StatusItemController(
            recent: { [unowned self] in RecentItem.items(from: model.config) },
            openAgain: { [unowned self] entry in
                receive(IncomingLink(url: entry.url, sourceApp: entry.sourceApp, receivedAt: Date()))
            },
            showSettings: { [unowned self] in showSettings() })
    }

    func showSettings() {
        if settings == nil { settings = SettingsWindowController(model: model) }
        settings?.show()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }
        var source: String?
        if let pid = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value {
            source = NSRunningApplication(processIdentifier: pid_t(pid))?.bundleIdentifier
        }
        receive(IncomingLink(url: url, sourceApp: source, receivedAt: Date()))
    }

    private func receive(_ link: IncomingLink) {
        switch Router.decide(link, state: model.config.routerState) {
        case .open(let target, _):
            open(link, in: target)
            model.config.recordOutcome(link, target: target.id)
        case .pick(let preselected):
            if queue.enqueue(link) { present(link, preselected: preselected) }
        }
    }

    private func present(_ link: IncomingLink, preselected: Target.ID?) {
        let targets = model.config.visible.compactMap { model.target($0) }
        picker.show(link, targets: targets, preselected: preselected) { [weak self] action in
            self?.finish(link, action)
        }
    }

    private func finish(_ link: IncomingLink, _ action: PickerAction) {
        switch action {
        case .open(let id, let always):
            model.config.recordPick(link, target: id, always: always)
            model.config.recordOutcome(link, target: id)
            if let target = model.target(id) {
                open(link, in: target)
            } else {
                Self.log.error("picked target \(id, privacy: .public) is not in the config")
            }
        case .copy(let url):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            model.config.recordOutcome(link, target: nil)
        case .cancel:
            model.config.recordOutcome(link, target: nil)
        }
        showNext()
    }

    /// Advances the queue; a waiting link that now routes without the picker (a rule was just
    /// made) opens directly instead of being shown.
    private func showNext() {
        var next = queue.resolveCurrent()
        while let link = next {
            switch Router.decide(link, state: model.config.routerState) {
            case .pick(let preselected):
                present(link, preselected: preselected)
                return
            case .open(let target, _):
                open(link, in: target)
                model.config.recordOutcome(link, target: target.id)
                next = queue.resolveCurrent()
            }
        }
    }

    private func open(_ link: IncomingLink, in target: Target) {
        let apps = model.discovered
            .first { $0.browser == target.browser && ($0.directory == (target.profile ?? "")) }?
            .installedWebApps ?? []
        let command: LaunchCommand
        if target.browser == .firefox,
           let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Browser.firefox.bundleID) {
            command = Launch.command(for: link.url, target: target, installedWebApps: apps, firefoxApp: app.path)
        } else {
            command = Launch.command(for: link.url, target: target, installedWebApps: apps)
        }
        do { try launcher.run(command) } catch {
            Self.log.error("launch failed for \(target.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
