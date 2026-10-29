import AppKit
import ManiculeCore

/// The icon-strip picker: a borderless panel under the pointer that takes keys without
/// activating the app. Built once and reused; each `show` refills it.
@MainActor
final class PickerPanel: NSObject, @MainActor Picking {
    static let tile: CGFloat = 76
    /// The extra space between browser groups, and before ⋯.
    static let groupGap: CGFloat = 12
    private static let padding: CGFloat = 10
    private static let headerHeight: CGFloat = 24

    let panel: KeyPanel
    private let content = PickerContentView()
    private let urlLabel = NSTextField(labelWithString: "")
    private let sourceLabel = NSTextField(labelWithString: "")
    let copyButton = HoverButton(title: "Copy", target: nil, action: nil)
    private let strip = NSStackView()

    private var model: PickerModel?
    private(set) var tiles: [TileView] = []
    let moreTile = MoreTileView()
    private var shownStrip: [[Target]]?
    private var completion: ((PickerAction) -> Void)?
    private var menuIsOpen = false
    /// Pops the ⋯ menu up under `tile`, with `highlighted` placed there; returns once it closes.
    var presentMenu: @MainActor (NSMenu, NSMenuItem?, NSView) -> Void = { menu, highlighted, tile in
        menu.popUp(positioning: highlighted, at: NSPoint(x: 0, y: -4), in: tile)
    }
    private var clickMonitor: Any?
    private var sourceNames: [String: String] = [:]

    override init() {
        panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: true)
        super.init()
        panel.delegate = self
        panel.level = .popUpMenu
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        panel.contentView = background

        content.translatesAutoresizingMaskIntoConstraints = false
        content.onKey = { [weak self] key in self?.handle(key) }
        background.addSubview(content)

        urlLabel.lineBreakMode = .byTruncatingMiddle
        urlLabel.font = .systemFont(ofSize: 12, weight: .medium)
        urlLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // The URL takes the slack, which pins the source name and Copy to the right edge.
        urlLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sourceLabel.font = .systemFont(ofSize: 11)
        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.setContentHuggingPriority(.required, for: .horizontal)
        copyButton.font = .systemFont(ofSize: 11, weight: .medium)
        copyButton.setContentHuggingPriority(.required, for: .horizontal)
        copyButton.target = self
        copyButton.action = #selector(copyClicked)
        copyButton.toolTip = "Copy the link without tracking parameters (C)"
        copyButton.refusesFirstResponder = true

        let header = NSStackView(views: [urlLabel, sourceLabel, copyButton])
        header.orientation = .horizontal
        header.spacing = 8
        header.distribution = .fill
        strip.orientation = .horizontal
        strip.spacing = 0
        strip.addArrangedSubview(moreTile)
        moreTile.onClick = { [weak self] in self?.handle(.more) }
        let column = NSStackView(views: [header, strip])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(column)

        let p = Self.padding
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            content.topAnchor.constraint(equalTo: background.topAnchor),
            content.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: p),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -p),
            column.topAnchor.constraint(equalTo: content.topAnchor, constant: p),
            column.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -p),
            header.heightAnchor.constraint(equalToConstant: Self.headerHeight),
            header.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
    }

    func show(_ link: IncomingLink, strip groups: [[Target]], more: [[Target]], preselected: Target.ID?,
              completion: @escaping (PickerAction) -> Void) {
        self.completion = completion
        let model = PickerModel(link: link, strip: groups, more: more, preselected: preselected)
        self.model = model
        urlLabel.stringValue = (link.url.host() ?? "") + link.url.path()
        urlLabel.toolTip = link.url.absoluteString
        sourceLabel.stringValue = link.sourceApp.flatMap(sourceName) ?? ""
        sourceLabel.isHidden = sourceLabel.stringValue.isEmpty
        fillStrip(groups)
        moreTile.isEnabled = model.moreIsEnabled
        refreshSelection()

        let tiles = CGFloat(model.pinned.count + 1) * Self.tile + CGFloat(groups.count) * Self.groupGap
        let width = max(tiles, 280) + Self.padding * 2
        let height = Self.headerHeight + 6 + Self.tile + Self.padding * 2
        panel.setFrame(Self.frame(size: NSSize(width: width, height: height), under: NSEvent.mouseLocation),
                       display: false)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(content)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(.cancel) }
        }
    }

    /// Centred under the pointer, kept inside the visible frame of the screen the pointer is on.
    static func frame(size: NSSize, under point: NSPoint) -> NSRect {
        var frame = NSRect(x: point.x - size.width / 2, y: point.y - size.height - 12,
                           width: size.width, height: size.height)
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return frame }
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        if frame.minY < visible.minY { frame.origin.y = point.y + 12 }
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        return frame
    }

    /// One tile per pinned target, numbered straight across the groups, with `groupGap` after
    /// each group (so also before ⋯, which stays the last arranged view).
    private func fillStrip(_ groups: [[Target]]) {
        if shownStrip == groups { return }
        shownStrip = groups
        tiles.forEach { $0.removeFromSuperview() }
        let targets = groups.flatMap { $0 }
        let details = Target.tileDetails(targets)
        tiles = targets.enumerated().map { index, target in
            let tile = TileView(target: target, number: index < 9 ? index + 1 : nil, detail: details[target.id])
            tile.onClick = { [weak self] in self?.finish(.open(target.id, always: false)) }
            strip.insertArrangedSubview(tile, at: index)
            return tile
        }
        var end = 0
        for group in groups {
            end += group.count
            if end > 0 { strip.setCustomSpacing(Self.groupGap, after: tiles[end - 1]) }
        }
    }

    private func refreshSelection() {
        for tile in tiles { tile.isSelected = model?.selection == .target(tile.target.id) }
        moreTile.isSelected = model?.selection == .more
    }

    private func handle(_ key: PickerKey) {
        guard model != nil else { return }
        switch model!.handle(key) {
        case .finish(let action): finish(action)
        case .showMore(let highlighted): showMore(highlighted: highlighted)
        case nil: refreshSelection()
        }
    }

    @objc private func copyClicked() { handle(.copy) }

    /// The ⋯ menu: a heading per browser, then each target; holding ⌥ swaps each item for its
    /// "always for this host" twin. Closing it without a choice leaves the picker up.
    private func showMore(highlighted: Target.ID?) {
        guard let model else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let host = model.link.url.host?.lowercased() ?? ""  // as `Config.recordPick` keys its rule
        var highlightedItem: NSMenuItem?
        for group in model.more {
            guard let browser = group.first?.browser else { continue }
            menu.addItem(.sectionHeader(title: browser.displayName))
            for target in group {
                let title = [target.shortName, target.email].compactMap { $0 }.joined(separator: " — ")
                let item = moreItem(title, target.id, always: false)
                menu.addItem(item)
                if target.id == highlighted { highlightedItem = item }
                guard !host.isEmpty else { continue }
                let always = moreItem("\(title) — always for \(host)", target.id, always: true)
                always.isAlternate = true
                always.keyEquivalentModifierMask = .option
                menu.addItem(always)
            }
        }
        menuIsOpen = true
        presentMenu(menu, highlightedItem, moreTile)
        menuIsOpen = false
        guard completion != nil else { return }
        // Escape or a click away closed the menu: back to the strip, keys and all.
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(content)
    }

    private func moreItem(_ title: String, _ id: Target.ID, always: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(moreItemChosen(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = MoreChoice(id: id, always: always)
        return item
    }

    @objc private func moreItemChosen(_ item: NSMenuItem) {
        guard let choice = item.representedObject as? MoreChoice else { return }
        finish(.open(choice.id, always: choice.always))
    }

    /// Hides the panel and completes exactly once.
    private func finish(_ action: PickerAction) {
        guard let completion else { return }
        self.completion = nil
        model = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        // A window being ordered out doesn't reliably get mouseExited, and tiles are reused.
        tiles.forEach { $0.clearHover() }
        moreTile.clearHover()
        copyButton.clearHover()
        panel.orderOut(nil)
        completion(action)
    }

    private func sourceName(_ bundleID: String) -> String? {
        if let name = sourceNames[bundleID] { return name }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: app.path)
            .replacingOccurrences(of: ".app", with: "", options: [.anchored, .backwards])
        sourceNames[bundleID] = name
        return name
    }
}

extension PickerPanel: NSWindowDelegate {
    /// Losing key without a click (⌘-Tab, Mission Control) would leave the panel deaf to keys
    /// and the link queue stalled, so it cancels like a click outside. The ⋯ menu is the
    /// exception: the picker takes key back when it closes.
    func windowDidResignKey(_ notification: Notification) {
        guard !menuIsOpen else { return }
        finish(.cancel)
    }
}

/// A ⋯ menu item's target and whether it also saves "always for this host".
private struct MoreChoice {
    let id: Target.ID
    let always: Bool
}

/// A borderless panel can't become key on its own; the picker needs key events.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Decodes key events into `PickerKey`s.
final class PickerContentView: NSView {
    var onKey: ((PickerKey) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if let key = Self.key(for: event) { onKey?(key) } else { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "c" else { return super.performKeyEquivalent(with: event) }
        onKey?(.copy)
        return true
    }

    static func key(for event: NSEvent) -> PickerKey? {
        switch event.keyCode {
        case 36, 76: return event.modifierFlags.contains(.option) ? .optionEnter : .enter
        case 53: return .escape
        case 123: return .left
        case 124: return .right
        default: break
        }
        guard let chars = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        if chars == "c" { return .copy }
        if chars == "0" { return .more }
        if let digit = Int(chars), (1...9).contains(digit) { return .digit(digit) }
        return nil
    }
}

/// A square tile in the strip: a picture, a name, an optional detail line under it and an
/// optional key badge. Draws the keyboard selection and the hover; a disabled tile is dimmed and
/// takes neither hover nor clicks.
class StripTileView: NSView {
    var onClick: (() -> Void)?
    var isSelected = false { didSet { needsDisplay = true } }
    var isEnabled = true {
        didSet {
            alphaValue = isEnabled ? 1 : 0.4
            if !isEnabled { isHovered = false }
        }
    }
    private(set) var isHovered = false { didSet { needsDisplay = true } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // .activeAlways: the panel never activates the app, so .activeInKeyWindow would never fire.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { if isEnabled { isHovered = true } }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    func clearHover() { isHovered = false }

    @MainActor
    init(image: NSImage, name: String, number: String?, detail: String?) {
        super.init(frame: NSRect(x: 0, y: 0, width: PickerPanel.tile, height: PickerPanel.tile))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: PickerPanel.tile),
            heightAnchor.constraint(equalToConstant: PickerPanel.tile),
        ])

        let image = NSImageView(image: image)
        image.imageScaling = .scaleProportionallyUpOrDown
        let name = NSTextField(labelWithString: name)
        name.font = .systemFont(ofSize: 10)
        name.alignment = .center
        name.lineBreakMode = .byTruncatingTail
        for view in [image, name] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let side: CGFloat = detail == nil ? 44 : 34  // room for the detail line within the tile
        NSLayoutConstraint.activate([
            image.centerXAnchor.constraint(equalTo: centerXAnchor),
            image.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            image.widthAnchor.constraint(equalToConstant: side),
            image.heightAnchor.constraint(equalToConstant: side),
            name.topAnchor.constraint(equalTo: image.bottomAnchor, constant: 4),
            name.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            name.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
        ])
        if let detail {
            let line = NSTextField(labelWithString: detail)
            line.font = .systemFont(ofSize: 9)
            line.textColor = .secondaryLabelColor
            line.alignment = .center
            line.lineBreakMode = .byTruncatingMiddle
            line.translatesAutoresizingMaskIntoConstraints = false
            addSubview(line)
            NSLayoutConstraint.activate([
                line.topAnchor.constraint(equalTo: name.bottomAnchor),
                line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
                line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            ])
        }

        if let number {
            let badge = NSTextField(labelWithString: number)
            badge.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
            badge.textColor = .secondaryLabelColor
            badge.translatesAutoresizingMaskIntoConstraints = false
            addSubview(badge)
            NSLayoutConstraint.activate([
                badge.topAnchor.constraint(equalTo: topAnchor, constant: 3),
                badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Keyboard selection is accent-tinted; hover is a neutral wash, so the two read apart and can stack.
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8)
        if isSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
            shape.fill()
        }
        if isHovered {
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            shape.fill()
        }
    }

    override func mouseDown(with event: NSEvent) { if isEnabled { onClick?() } }
}

/// One target in the strip: its picture, number and short name, plus a detail line (account or
/// folder) when another tile shares the short name; the tooltip adds the full name and email.
final class TileView: StripTileView {
    let target: Target
    let detail: String?

    @MainActor
    init(target: Target, number: Int?, detail: String? = nil) {
        self.target = target
        self.detail = detail
        super.init(image: ProfileIcon.image(for: target), name: target.shortName, number: number.map(String.init),
                   detail: detail)
        toolTip = [target.name, target.email].compactMap { $0 }.joined(separator: "\n")
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}

/// The strip's last tile: the menu of available targets that aren't pinned (key `0`).
final class MoreTileView: StripTileView {
    @MainActor
    init() {
        let image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "More") ?? NSImage()
        super.init(image: image, name: "More", number: "0", detail: nil)
        toolTip = "More profiles (0)"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isEnabled: Bool {
        didSet { toolTip = isEnabled ? "More profiles (0)" : "Every profile is pinned" }
    }
}

/// A borderless text button with a rounded background that brightens under the pointer.
final class HoverButton: NSButton {
    private(set) var isHovered = false { didSet { needsDisplay = true } }

    convenience init(title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + 16, height: max(size.height + 4, 20))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    func clearHover() { isHovered = false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(isHovered ? 0.16 : 0.07).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        super.draw(dirtyRect)
    }
}
