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
        // After launch completes, so the pictures' file reads don't hold it up.
        DispatchQueue.main.async { [unowned self] in ProfileIcon.prewarm(model.routerState.pickerTargets) }
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
        let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue ?? ""
        guard let url = URL(string: string) else {
            Self.log.error("ignored a link that isn't a URL: \(string, privacy: .private)")
            return
        }
        accept(url, from: event)
    }

    /// HTML files opened with Manicule (it is listed as their viewer as the default browser).
    func application(_ application: NSApplication, open urls: [URL]) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        for url in urls { accept(url, from: event) }
    }

    private func accept(_ url: URL, from event: NSAppleEventDescriptor?) {
        guard IncomingLink.isHandled(url) else {
            Self.log.error("ignored a \(url.scheme ?? "scheme-less", privacy: .public) link: \(url.absoluteString, privacy: .private)")
            return
        }
        var source: String?
        if let pid = event?.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value {
            source = NSRunningApplication(processIdentifier: pid_t(pid))?.bundleIdentifier
        }
        receive(IncomingLink(url: url, sourceApp: source, receivedAt: Date()))
    }

    private func receive(_ link: IncomingLink) {
        switch Router.decide(link, state: model.routerState) {
        case .open(let target, _):
            open(link, in: target)
            model.config.recordOutcome(link, target: target.id)
        case .pick(let preselected):
            if queue.enqueue(link) { present(link, preselected: preselected) }
        }
    }

    private func present(_ link: IncomingLink, preselected: Target.ID?) {
        let state = model.routerState
        picker.show(link, strip: state.pickerGroups, more: state.overflowGroups, preselected: preselected) { [weak self] action in
            self?.finish(link, action)
        }
    }

    private func finish(_ link: IncomingLink, _ action: PickerAction) {
        switch action {
        case .open(let id, let always):
            // Launch first: recording saves the config, which the link shouldn't wait on.
            if let target = model.routerState.target(id) {
                open(link, in: target)
            } else {
                Self.log.error("picked target \(id, privacy: .public) can't open on this Mac")
            }
            model.config.recordPick(link, target: id, always: always)
            model.config.recordOutcome(link, target: id)
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
            switch Router.decide(link, state: model.routerState) {
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
