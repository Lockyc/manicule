import XCTest
@testable import ManiculeCore

final class SmokeTests: XCTestCase {
    func testPackageName() {
        XCTAssertEqual(Manicule.name, "manicule")
    }
}
