import AppKit
import ManiculeCore

/// The icon-strip picker: a borderless panel under the pointer that takes keys without
/// activating the app. Built once and reused; each `show` refills it.
@MainActor
final class PickerPanel: NSObject, @MainActor Picking {
    static let tile: CGFloat = 76
    private static let padding: CGFloat = 10
    private static let headerHeight: CGFloat = 24

    let panel: KeyPanel
    private let content = PickerContentView()
    private let urlLabel = NSTextField(labelWithString: "")
    private let sourceLabel = NSTextField(labelWithString: "")
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private let strip = NSStackView()

    private var model: PickerModel?
    private var tiles: [TileView] = []
    private var completion: ((PickerAction) -> Void)?
    private var clickMonitor: Any?
    private var sourceNames: [String: String] = [:]

    override init() {
        panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: true)
        super.init()
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
        sourceLabel.font = .systemFont(ofSize: 11)
        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.setContentHuggingPriority(.required, for: .horizontal)
        copyButton.bezelStyle = .accessoryBarAction
        copyButton.controlSize = .small
        copyButton.target = self
        copyButton.action = #selector(copyClicked)
        copyButton.toolTip = "Copy the link without tracking parameters (C)"
        copyButton.refusesFirstResponder = true

        let header = NSStackView(views: [urlLabel, sourceLabel, copyButton])
        header.orientation = .horizontal
        header.spacing = 8
        strip.orientation = .horizontal
        strip.spacing = 0
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

    func show(_ link: IncomingLink, targets: [Target], preselected: Target.ID?,
              completion: @escaping (PickerAction) -> Void) {
        self.completion = completion
        model = PickerModel(link: link, targets: targets, preselected: preselected)
        urlLabel.stringValue = (link.url.host() ?? "") + link.url.path()
        urlLabel.toolTip = link.url.absoluteString
        sourceLabel.stringValue = link.sourceApp.flatMap(sourceName) ?? ""
        sourceLabel.isHidden = sourceLabel.stringValue.isEmpty
        fillStrip(targets)
        refreshSelection()

        let width = max(CGFloat(max(targets.count, 3)) * Self.tile, 280) + Self.padding * 2
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

    private func fillStrip(_ targets: [Target]) {
        if tiles.map(\.target) == targets { return }
        tiles.forEach { $0.removeFromSuperview() }
        tiles = targets.enumerated().map { index, target in
            let tile = TileView(target: target, number: index < 9 ? index + 1 : nil)
            tile.onClick = { [weak self] in self?.finish(.open(target.id, always: false)) }
            strip.addArrangedSubview(tile)
            return tile
        }
    }

    private func refreshSelection() {
        for tile in tiles { tile.isSelected = tile.target.id == model?.selection }
    }

    private func handle(_ key: PickerKey) {
        guard model != nil else { return }
        if let action = model!.handle(key) { finish(action) } else { refreshSelection() }
    }

    @objc private func copyClicked() { handle(.copy) }

    /// Hides the panel and completes exactly once.
    private func finish(_ action: PickerAction) {
        guard let completion else { return }
        self.completion = nil
        model = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
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
        if let digit = Int(chars), (1...9).contains(digit) { return .digit(digit) }
        return nil
    }
}

/// One target in the strip: its picture, number and short name; the tooltip adds the full name and email.
final class TileView: NSView {
    let target: Target
    var onClick: (() -> Void)?
    var isSelected = false { didSet { needsDisplay = true } }

    @MainActor
    init(target: Target, number: Int?) {
        self.target = target
        super.init(frame: NSRect(x: 0, y: 0, width: PickerPanel.tile, height: PickerPanel.tile))
        toolTip = [target.name, target.email].compactMap { $0 }.joined(separator: "\n")
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: PickerPanel.tile),
            heightAnchor.constraint(equalToConstant: PickerPanel.tile),
        ])

        let image = NSImageView(image: ProfileIcon.image(for: target))
        image.imageScaling = .scaleProportionallyUpOrDown
        let name = NSTextField(labelWithString: target.shortName)
        name.font = .systemFont(ofSize: 10)
        name.alignment = .center
        name.lineBreakMode = .byTruncatingTail
        for view in [image, name] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            image.centerXAnchor.constraint(equalTo: centerXAnchor),
            image.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            image.widthAnchor.constraint(equalToConstant: 44),
            image.heightAnchor.constraint(equalToConstant: 44),
            name.topAnchor.constraint(equalTo: image.bottomAnchor, constant: 4),
            name.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            name.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
        ])

        if let number {
            let badge = NSTextField(labelWithString: "\(number)")
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

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8).fill()
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
}
