import AppKit
import ManiculeCore
import os

/// Stand-in until the picker panel lands: takes the preselected target, else cancels.
final class StubPicker: Picking {
    func show(_ link: IncomingLink, targets: [Target], preselected: Target.ID?,
              completion: @escaping (PickerAction) -> Void) {
        completion(preselected.map { .open($0, always: false) } ?? .cancel)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "com.lockyc.manicule", category: "app")

    private let store: ConfigStore
    private let launcher = Launcher()
    private var picker: Picking = StubPicker()
    private var queue = LinkQueue()
    private var discovered: [DiscoveredProfile] = []
    private var config: Config

    override init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = ConfigStore(directory: support.appendingPathComponent("Manicule"))
        config = Config(targets: [], visible: [])
        super.init()
        reload()
    }

    /// Re-reads installed browser profiles and the saved config. Also run when Settings opens.
    func reload() {
        discovered = ProfileDiscovery.discoverAll(home: FileManager.default.homeDirectoryForCurrentUser)
        config = store.load(discovered: discovered)
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
        switch Router.decide(link, state: config.routerState) {
        case .open(let target, _):
            open(link, in: target)
            config.recordOutcome(link, target: target.id)
            persist()
        case .pick(let preselected):
            if queue.enqueue(link) { present(link, preselected: preselected) }
        }
    }

    private func present(_ link: IncomingLink, preselected: Target.ID?) {
        let targets = config.visible.compactMap { id in config.targets.first { $0.id == id } }
        picker.show(link, targets: targets, preselected: preselected) { [weak self] action in
            self?.finish(link, action)
        }
    }

    private func finish(_ link: IncomingLink, _ action: PickerAction) {
        switch action {
        case .open(let id, let always):
            config.recordPick(link, target: id, always: always)
            config.recordOutcome(link, target: id)
            if let target = config.targets.first(where: { $0.id == id }) { open(link, in: target) }
        case .copy(let url):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            config.recordOutcome(link, target: nil)
        case .cancel:
            config.recordOutcome(link, target: nil)
        }
        persist()
        showNext()
    }

    /// Advances the queue; a waiting link that now routes without the picker (a rule was just
    /// made) opens directly instead of being shown.
    private func showNext() {
        var next = queue.resolveCurrent()
        while let link = next {
            switch Router.decide(link, state: config.routerState) {
            case .pick(let preselected):
                present(link, preselected: preselected)
                return
            case .open(let target, _):
                open(link, in: target)
                config.recordOutcome(link, target: target.id)
                persist()
                next = queue.resolveCurrent()
            }
        }
    }

    private func open(_ link: IncomingLink, in target: Target) {
        let apps = discovered.first { $0.browser == target.browser && ($0.directory == (target.profile ?? "")) }?
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

    private func persist() {
        do { try store.save(config) } catch {
            Self.log.error("config save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
