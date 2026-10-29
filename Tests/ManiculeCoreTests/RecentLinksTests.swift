import XCTest
@testable import ManiculeCore

final class RecentLinksTests: XCTestCase {
    private let work = Target(id: "chrome|P1", browser: .chrome, profile: "P1", name: "Chrome · Work", email: nil)

    private func entry(_ s: String, target: Target.ID?, at t: TimeInterval) -> HistoryEntry {
        HistoryEntry(url: URL(string: s)!, sourceApp: nil, target: target, at: Date(timeIntervalSince1970: t))
    }

    func testNewestFirstWithTargetNames() {
        let config = Config(targets: [work], visible: [work.id], history: [
            entry("https://a.example.com/x", target: work.id, at: 1),
            entry("https://b.example.com/y?q=1", target: nil, at: 2),
        ])
        let items = RecentItem.items(from: config)
        XCTAssertEqual(items.map(\.title), ["b.example.com — Copied or cancelled", "a.example.com — Chrome · Work"])
        XCTAssertEqual(items[0].tooltip, "https://b.example.com/y?q=1")
    }

    func testCapsAtTwentyKeepingNewest() {
        let history = (0..<30).map { entry("https://h\($0).com/", target: nil, at: TimeInterval($0)) }
        let items = RecentItem.items(from: Config(targets: [], visible: [], history: history))
        XCTAssertEqual(items.count, 20)
        XCTAssertEqual(items.first?.entry.url.host, "h29.com")
        XCTAssertEqual(items.last?.entry.url.host, "h10.com")
    }

    func testEmptyHistoryHasNoItems() {
        XCTAssertTrue(RecentItem.items(from: Config(targets: [], visible: [])).isEmpty)
    }

    func testUnknownTargetIdFallsBackToUnresolvedName() {
        let config = Config(targets: [], visible: [], history: [entry("https://a.com/", target: "gone", at: 1)])
        XCTAssertEqual(RecentItem.items(from: config).first?.title, "a.com — Copied or cancelled")
    }
}
