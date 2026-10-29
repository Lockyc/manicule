import XCTest
@testable import ManiculeCore

final class TrackingParametersTests: XCTestCase {
    private func strip(_ s: String) -> String {
        TrackingParameters.stripped(URL(string: s)!).absoluteString
    }

    func testStripsUTMAndClickIDs() {
        XCTAssertEqual(strip("https://example.com/p?a=1&utm_source=x&fbclid=y"), "https://example.com/p?a=1")
    }

    func testRemovesEmptyQuery() {
        XCTAssertEqual(strip("https://example.com/p?utm_medium=x"), "https://example.com/p")
    }

    func testKeepsFragmentAndOrder() {
        XCTAssertEqual(strip("https://example.com/p?b=2&gclid=z&a=1#frag"), "https://example.com/p?b=2&a=1#frag")
    }

    func testCaseInsensitiveNames() {
        XCTAssertEqual(strip("https://example.com/p?UTM_Source=x&FBCLID=y&k=v"), "https://example.com/p?k=v")
    }

    func testURLWithoutQueryUnchanged() {
        XCTAssertEqual(strip("https://example.com/p#frag"), "https://example.com/p#frag")
    }
}
