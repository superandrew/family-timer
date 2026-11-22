import XCTest
@testable import FamilyTimerCore

final class VersionTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertEqual(FamilyTimer.version, "0.1.0-dev")
    }
}
