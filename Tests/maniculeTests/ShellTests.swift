import XCTest
import ManiculeCore
@testable import manicule

final class ShellTests: XCTestCase {
    func testShellSeesCoreAcrossModuleBoundary() {
        XCTAssertEqual(Manicule.name, "manicule")
    }
}
