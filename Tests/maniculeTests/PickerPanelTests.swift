import AppKit
import ManiculeCore
import XCTest
@testable import manicule

/// The picker panel driven with synthetic key events — no focus or window-server input needed.
@MainActor
final class PickerPanelTests: XCTestCase {
    override func setUp() { _ = NSApplication.shared }

    private let targets = [
        Target(id: "first", browser: .chrome, profile: "Default", name: "First", email: "one@example.com"),
        Target(id: "second", browser: .chromium, profile: "Profile 1", name: "Second", email: nil),
        Target(id: "safari", browser: .safari, profile: nil, name: "Safari", email: nil),
    ]
    private let link = IncomingLink(url: URL(string: "https://example.com/a/b?utm_source=x")!,
                                    sourceApp: nil, receivedAt: Date())

    private func key(_ characters: String, _ keyCode: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    private func show(_ picker: PickerPanel, preselected: Target.ID? = nil) -> () -> [PickerAction] {
        var actions: [PickerAction] = []
        picker.show(link, targets: targets, preselected: preselected) { actions.append($0) }
        return { actions }
    }

    func testKeyTwoOpensSecondTarget() throws {
        let picker = PickerPanel()
        let actions = show(picker)
        let responder = try XCTUnwrap(picker.panel.firstResponder)
        responder.keyDown(with: key("2", 19))
        XCTAssertEqual(actions(), [.open("second", always: false)])
        XCTAssertFalse(picker.panel.isVisible, "the panel hides once it completes")
        responder.keyDown(with: key("1", 18))
        XCTAssertEqual(actions().count, 1, "completes exactly once")
    }

    func testReusedPanelTakesArrowsThenOptionReturn() throws {
        let picker = PickerPanel()
        let first = show(picker)
        picker.panel.firstResponder?.keyDown(with: key("\u{1B}", 53))
        XCTAssertEqual(first(), [.cancel])

        let second = show(picker, preselected: "second")
        let responder = try XCTUnwrap(picker.panel.firstResponder)
        responder.keyDown(with: key(String(UnicodeScalar(NSRightArrowFunctionKey)!), 124))
        responder.keyDown(with: key("\r", 36, .option))
        XCTAssertEqual(second(), [.open("safari", always: true)])
    }

    func testCopyKeyCompletesWithStrippedURL() throws {
        let picker = PickerPanel()
        let actions = show(picker)
        picker.panel.firstResponder?.keyDown(with: key("c", 8))
        XCTAssertEqual(actions(), [.copy(TrackingParameters.stripped(link.url))])
    }

    func testCopyButtonSitsAtTheRightEdge() throws {
        let picker = PickerPanel()
        _ = show(picker)
        let content = try XCTUnwrap(picker.panel.contentView)
        content.layoutSubtreeIfNeeded()
        let copy = picker.copyButton.convert(picker.copyButton.bounds, to: content)
        XCTAssertEqual(copy.maxX, content.bounds.maxX - 10, accuracy: 1, "flush with the right padding")
        picker.panel.firstResponder?.keyDown(with: key("\u{1B}", 53))
    }

    func testTilesAndCopyHighlightOnHover() throws {
        let picker = PickerPanel()
        _ = show(picker)
        let tile = try XCTUnwrap(picker.tiles.first)
        let mouse = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0,
                                                     windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        XCTAssertFalse(tile.trackingAreas.isEmpty)
        tile.mouseEntered(with: mouse)
        XCTAssertTrue(tile.isHovered)
        tile.mouseExited(with: mouse)
        XCTAssertFalse(tile.isHovered)
        XCTAssertFalse(picker.copyButton.trackingAreas.isEmpty)
        picker.copyButton.mouseEntered(with: mouse)
        XCTAssertTrue(picker.copyButton.isHovered)
        picker.panel.firstResponder?.keyDown(with: key("\u{1B}", 53))
    }

    func testHoverDoesNotSurviveIntoTheNextShow() throws {
        let picker = PickerPanel()
        let first = show(picker)
        let mouse = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0,
                                                     windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        let tile = try XCTUnwrap(picker.tiles.first)
        tile.mouseEntered(with: mouse)
        picker.copyButton.mouseEntered(with: mouse)
        tile.mouseDown(with: mouse)
        XCTAssertEqual(first(), [.open("first", always: false)])

        _ = show(picker)
        XCTAssertTrue(picker.tiles.first === tile, "same targets reuse the tiles")
        XCTAssertFalse(tile.isHovered)
        XCTAssertFalse(picker.copyButton.isHovered)
        picker.panel.firstResponder?.keyDown(with: key("\u{1B}", 53))
    }

    func testTilesSharingAShortNameShowTheirAccountOnTheTile() throws {
        let picker = PickerPanel()
        let twins = [
            Target(id: "x", browser: .chrome, profile: "Default", name: "Chrome · Work", email: "one@example.com"),
            Target(id: "y", browser: .chrome, profile: "Profile 1", name: "Chrome · Work", email: nil),
            Target(id: "safari", browser: .safari, profile: nil, name: "Safari", email: nil),
        ]
        picker.show(link, targets: twins, preselected: nil) { _ in }
        XCTAssertEqual(picker.tiles.map(\.detail), ["one@example.com", "Profile 1", nil])
        let labels = picker.tiles[0].subviews.compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(labels.contains("one@example.com"), "\(labels)")
        picker.panel.firstResponder?.keyDown(with: key("\u{1B}", 53))
    }

    func testResigningKeyCancels() {
        let picker = PickerPanel()
        let actions = show(picker)
        picker.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: picker.panel))
        XCTAssertEqual(actions(), [.cancel])
        XCTAssertFalse(picker.panel.isVisible)
    }

    func testFrameStaysOnScreen() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let corner = NSPoint(x: screen.visibleFrame.maxX - 1, y: screen.visibleFrame.minY + 1)
        let frame = PickerPanel.frame(size: NSSize(width: 300, height: 120), under: corner)
        XCTAssertTrue(screen.visibleFrame.contains(frame))
    }
}

@MainActor
final class ProfileIconTests: XCTestCase {
    func testNeighbouringProfileIdsSpreadAcrossTheWheel() {
        let hues = (1...6).map { ProfileIcon.hue("chromium|Profile \($0)") }
        XCTAssertGreaterThan(hues.max()! - hues.min()!, 0.5, "ids differing in one character must not cluster")
        XCTAssertEqual(Set(hues).count, hues.count)
        XCTAssertEqual(ProfileIcon.hue("chrome|Default"), ProfileIcon.hue("chrome|Default"))
    }

    func testPrewarmFillsTheCache() {
        let target = Target(id: "chromium|Prewarm \(UUID().uuidString)", browser: .chromium, profile: "Nope",
                            name: "Chromium · Prewarm", email: nil)
        XCTAssertFalse(ProfileIcon.isCached(target.id))
        ProfileIcon.prewarm([target])
        XCTAssertTrue(ProfileIcon.isCached(target.id))
    }
}
