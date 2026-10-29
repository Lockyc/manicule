import XCTest
@testable import ManiculeCore

final class LinkQueueTests: XCTestCase {
    private func link(_ s: String) -> IncomingLink {
        IncomingLink(url: URL(string: s)!, sourceApp: nil, receivedAt: Date(timeIntervalSince1970: 0))
    }

    func testFirstLinkShowsImmediately() {
        var q = LinkQueue()
        XCTAssertTrue(q.enqueue(link("https://a.test")))
        XCTAssertEqual(q.current, link("https://a.test"))
    }

    func testSecondLinkWaitsThenShows() {
        var q = LinkQueue()
        XCTAssertTrue(q.enqueue(link("https://a.test")))
        XCTAssertFalse(q.enqueue(link("https://b.test")))
        XCTAssertEqual(q.current, link("https://a.test"))
        XCTAssertEqual(q.resolveCurrent(), link("https://b.test"))
        XCTAssertEqual(q.current, link("https://b.test"))
    }

    func testNoLinksLost() {
        var q = LinkQueue()
        _ = q.enqueue(link("https://a.test"))
        _ = q.enqueue(link("https://b.test"))
        _ = q.enqueue(link("https://c.test"))
        XCTAssertEqual(q.resolveCurrent(), link("https://b.test"))
        XCTAssertEqual(q.resolveCurrent(), link("https://c.test"))
        XCTAssertNil(q.resolveCurrent())
        XCTAssertNil(q.current)
    }
}
