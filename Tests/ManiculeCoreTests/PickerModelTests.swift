import XCTest
@testable import ManiculeCore

final class PickerModelTests: XCTestCase {
    private let targets = [
        Target(id: "a", browser: .chrome, profile: "Default", name: "Alpha", email: "a@example.com"),
        Target(id: "b", browser: .chrome, profile: "Profile 1", name: "Beta", email: nil),
        Target(id: "c", browser: .safari, profile: nil, name: "Safari", email: nil),
    ]
    private let link = IncomingLink(url: URL(string: "https://example.com/p?utm_source=x&id=7")!,
                                    sourceApp: nil, receivedAt: Date(timeIntervalSince1970: 0))

    private func model(preselected: Target.ID? = nil) -> PickerModel {
        PickerModel(link: link, targets: targets, preselected: preselected)
    }

    func testDigitOpensNthTarget() {
        var m = model()
        XCTAssertEqual(m.handle(.digit(2)), .open("b", always: false))
    }

    func testDigitBeyondCountIgnored() {
        var m = model()
        XCTAssertNil(m.handle(.digit(4)))
        XCTAssertNil(m.handle(.digit(0)))
    }

    func testEnterOpensSelection() {
        var m = model(preselected: "c")
        XCTAssertEqual(m.handle(.enter), .open("c", always: false))
        var first = model()
        XCTAssertEqual(first.handle(.enter), .open("a", always: false), "no preselection selects the first")
    }

    func testOptionEnterOpensAlways() {
        var m = model(preselected: "b")
        XCTAssertEqual(m.handle(.optionEnter), .open("b", always: true))
    }

    func testCopyReturnsStrippedURL() {
        var m = model()
        XCTAssertEqual(m.handle(.copy), .copy(TrackingParameters.stripped(link.url)))
    }

    func testEscapeCancels() {
        var m = model()
        XCTAssertEqual(m.handle(.escape), .cancel)
    }

    func testArrowsMoveSelectionAndClamp() {
        var m = model()
        XCTAssertNil(m.handle(.left))
        XCTAssertEqual(m.selection, "a", "clamped at the start")
        XCTAssertNil(m.handle(.right))
        XCTAssertEqual(m.selection, "b")
        _ = m.handle(.right)
        _ = m.handle(.right)
        XCTAssertEqual(m.selection, "c", "clamped at the end")
        _ = m.handle(.left)
        XCTAssertEqual(m.selection, "b")
    }

    func testUnknownPreselectionFallsBackToFirst() {
        XCTAssertEqual(model(preselected: "zzz").selection, "a")
    }

    func testEmptyTargetsOnlyCopyOrCancel() {
        var m = PickerModel(link: link, targets: [], preselected: nil)
        XCTAssertNil(m.selection)
        XCTAssertNil(m.handle(.enter))
        XCTAssertNil(m.handle(.right))
        XCTAssertEqual(m.handle(.escape), .cancel)
    }
}
