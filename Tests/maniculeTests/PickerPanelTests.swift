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

    func testFrameStaysOnScreen() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let corner = NSPoint(x: screen.visibleFrame.maxX - 1, y: screen.visibleFrame.minY + 1)
        let frame = PickerPanel.frame(size: NSSize(width: 300, height: 120), under: corner)
        XCTAssertTrue(screen.visibleFrame.contains(frame))
    }
}
