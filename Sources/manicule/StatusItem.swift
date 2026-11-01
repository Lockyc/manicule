import AppKit
import ManiculeCore
import Sparkle

/// The menu bar item. Rebuilds its menu each time it opens so Recent is current.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let recent: () -> [RecentItem]
    private let openAgain: (HistoryEntry) -> Void
    private let showSettings: () -> Void
    private let updater: SPUStandardUpdaterController?

    init(recent: @escaping () -> [RecentItem], openAgain: @escaping (HistoryEntry) -> Void,
         showSettings: @escaping () -> Void, updater: SPUStandardUpdaterController?) {
        self.recent = recent
        self.openAgain = openAgain
        self.showSettings = showSettings
        self.updater = updater
        super.init()
        item.button?.image = MenuBarIcon.image()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let recentItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Recent")
        let items = recent()
        if items.isEmpty {
            let empty = NSMenuItem(title: "No links yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }
        for entry in items {
            let row = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
            row.toolTip = entry.tooltip
            let actions = NSMenu(title: entry.title)
            actions.addItem(action("Open Again") { [weak self] in self?.openAgain(entry.entry) })
            actions.addItem(action("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(TrackingParameters.stripped(entry.entry.url).absoluteString, forType: .string)
            })
            row.submenu = actions
            submenu.addItem(row)
        }
        recentItem.submenu = submenu
        menu.addItem(recentItem)
        menu.addItem(.separator())
        menu.addItem(action("Settings…", key: ",") { [weak self] in self?.showSettings() })
        let check = action("Check for Updates…") { [weak self] in self?.updater?.checkForUpdates(nil) }
        if updater == nil {
            check.action = nil  // a nil action is what disables an item in an auto-enabling menu
            check.toolTip = "Only the installed Manicule.app updates itself"
        }
        menu.addItem(check)
        menu.addItem(NSMenuItem(title: "Quit Manicule", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func action(_ title: String, key: String = "", _ handler: @escaping () -> Void) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: key)
        let target = MenuAction(handler)
        menuItem.target = target
        menuItem.representedObject = target  // retains the handler for the item's lifetime
        return menuItem
    }
}

@MainActor
private final class MenuAction: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func run() { handler() }
}
