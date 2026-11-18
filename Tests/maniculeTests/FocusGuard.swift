import AppKit
import ObjectiveC
import XCTest

/// The base of every shell test. While a test runs, activating the app and making a window key
/// are refused (they would take the operator's keyboard) and fail the test, as does ordering an
/// opaque window onto a screen; a test that ends with the app active, a key window or an opaque
/// visible window fails too. It wraps `invokeTest`, so a subclass's own `setUp`/`tearDown`
/// can't skip it.
@MainActor
class FocusGuardedTestCase: XCTestCase {
    override func invokeTest() {
        FocusGuard.install
        FocusGuard.seen = []
        FocusGuard.isArmed = true
        super.invokeTest()
        FocusGuard.isArmed = false
        for violation in FocusGuard.seen { XCTFail(violation) }
        assertFocusSafe()
    }

    struct WindowState {
        var name: String
        var isKey: Bool
        var isVisible: Bool
        var alpha: CGFloat
    }

    /// What in this end state would take the operator's focus, one line each.
    nonisolated static func violations(appIsActive: Bool, windows: [WindowState]) -> [String] {
        (appIsActive ? ["the test app is active"] : [])
            + windows.flatMap { w in
                (w.isKey ? ["\(w.name) is the key window"] : [])
                    + (w.isVisible && w.alpha > 0 ? ["\(w.name) is on screen and not transparent"] : [])
            }
    }

    func assertFocusSafe(file: StaticString = #filePath, line: UInt = #line) {
        guard let app = NSApp else { return }
        let windows = app.windows.map {
            WindowState(name: FocusGuard.name($0), isKey: $0.isKeyWindow, isVisible: $0.isVisible, alpha: $0.alphaValue)
        }
        for violation in Self.violations(appIsActive: app.isActive, windows: windows) {
            XCTFail(violation, file: file, line: line)
        }
    }
}

/// The calls a shell test must not make, swapped for recording versions while a test runs.
@MainActor
enum FocusGuard {
    static var isArmed = false
    static var seen: [String] = []

    static func name(_ window: NSWindow) -> String { "\(type(of: window)) \"\(window.title)\"" }

    static let install: Void = {
        swap(NSWindow.self, #selector(NSWindow.makeKey), #selector(NSWindow.focusGuardMakeKey))
        swap(NSWindow.self, #selector(NSWindow.makeKeyAndOrderFront(_:)), #selector(NSWindow.focusGuardMakeKeyAndOrderFront(_:)))
        swap(NSWindow.self, #selector(NSWindow.order(_:relativeTo:)), #selector(NSWindow.focusGuardOrder(_:relativeTo:)))
        swap(NSApplication.self, #selector(NSApplication.activate(ignoringOtherApps:)),
             #selector(NSApplication.focusGuardActivate(ignoringOtherApps:)))
        swap(NSApplication.self, NSSelectorFromString("activate"), #selector(NSApplication.focusGuardActivatePlain))
    }()

    private static func swap(_ cls: AnyClass, _ original: Selector, _ replacement: Selector) {
        guard let a = class_getInstanceMethod(cls, original), let b = class_getInstanceMethod(cls, replacement) else {
            preconditionFailure("FocusGuard: \(cls) has no \(original)")
        }
        method_exchangeImplementations(a, b)
    }
}

extension NSWindow {
    /// Refused while a test runs: a key panel takes the operator's keyboard.
    @objc func focusGuardMakeKey() {
        guard FocusGuard.isArmed else { return focusGuardMakeKey() }
        FocusGuard.seen.append("\(FocusGuard.name(self)) was made key")
    }

    @objc func focusGuardMakeKeyAndOrderFront(_ sender: Any?) {
        guard FocusGuard.isArmed else { return focusGuardMakeKeyAndOrderFront(sender) }
        FocusGuard.seen.append("\(FocusGuard.name(self)) was made key and ordered front")
    }

    @objc func focusGuardOrder(_ place: NSWindow.OrderingMode, relativeTo other: Int) {
        focusGuardOrder(place, relativeTo: other)
        guard FocusGuard.isArmed, place != .out, alphaValue > 0,
              NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) else { return }
        FocusGuard.seen.append("\(FocusGuard.name(self)) was ordered onto a screen while opaque")
    }
}

extension NSApplication {
    /// Refused while a test runs: activating the test app takes the operator's focus.
    @objc func focusGuardActivate(ignoringOtherApps flag: Bool) {
        guard FocusGuard.isArmed else { return focusGuardActivate(ignoringOtherApps: flag) }
        FocusGuard.seen.append("the test app was activated")
    }

    @objc func focusGuardActivatePlain() {
        guard FocusGuard.isArmed else { return focusGuardActivatePlain() }
        FocusGuard.seen.append("the test app was activated")
    }
}

/// The guard shown to fire. Nothing here can take focus: the guard refuses the key and activate
/// calls it records, a window left opaque sits off every screen, and the one ordered onto a
/// screen is a single click-through point at alpha 0.01, ordered behind every window and out again.
final class FocusGuardTests: FocusGuardedTestCase {
    override func setUp() { _ = NSApplication.shared }

    private func window(at origin: CGPoint) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: origin, size: CGSize(width: 40, height: 40)),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    /// The 0f51da7 pattern: a picker panel made key and ordered front by its default seam.
    func testMakingAWindowKeyIsRefusedAndFails() {
        let window = window(at: CGPoint(x: -20_000, y: -20_000))
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
        XCTAssertFalse(window.isVisible, "the guard refused to show it")
        XCTAssertEqual(FocusGuard.seen.count, 2)
        FocusGuard.seen = []
    }

    /// SettingsWindowController.show's NSApp.activate().
    func testActivatingTheAppIsRefusedAndFails() {
        NSApp.activate()
        NSApp.activate(ignoringOtherApps: true)
        XCTAssertFalse(NSApp.isActive)
        XCTAssertEqual(FocusGuard.seen, ["the test app was activated", "the test app was activated"])
        FocusGuard.seen = []
    }

    /// A refused call left in `seen` fails the test that made it, after the test body returns.
    func testARefusedCallFailsTheTest() {
        XCTExpectFailure("the refused makeKey fails the test")
        window(at: CGPoint(x: -20_000, y: -20_000)).makeKey()
    }

    func testOrderingAnOpaqueWindowOntoAScreenIsRecorded() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first, "needs a screen to order onto")
        let window = window(at: screen.frame.origin)
        window.setContentSize(CGSize(width: 1, height: 1))
        window.alphaValue = 0.01
        window.ignoresMouseEvents = true
        window.orderBack(nil)
        window.orderOut(nil)
        XCTAssertEqual(FocusGuard.seen, ["NSWindow \"\" was ordered onto a screen while opaque"])
        FocusGuard.seen = []
    }

    func testAnOpaqueWindowLeftVisibleFailsTheEndCheck() {
        let window = window(at: CGPoint(x: -20_000, y: -20_000))
        window.orderBack(nil)
        XCTAssertEqual(FocusGuard.seen, [], "off every screen, ordering in is not a violation")
        XCTExpectFailure("an opaque window still visible when the test ends") { assertFocusSafe() }
        window.orderOut(nil)
    }

    func testAKeyWindowOrAnActiveAppIsAnEndStateViolation() {
        let hidden = WindowState(name: "panel", isKey: false, isVisible: true, alpha: 0)
        XCTAssertEqual(Self.violations(appIsActive: false, windows: [hidden]), [])
        XCTAssertEqual(Self.violations(appIsActive: false,
                                       windows: [WindowState(name: "panel", isKey: true, isVisible: false, alpha: 0)]),
                       ["panel is the key window"])
        XCTAssertEqual(Self.violations(appIsActive: true, windows: [hidden]), ["the test app is active"])
    }
}
