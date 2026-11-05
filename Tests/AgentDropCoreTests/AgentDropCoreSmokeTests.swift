import XCTest
@testable import AgentDropCore

final class AgentDropCoreSmokeTests: XCTestCase {
    func testVersionConstantIsAvailable() {
        XCTAssertEqual(AgentDropVersion.current, "0.2.10")
        XCTAssertEqual(AgentDropVersion.build, "12")
        XCTAssertEqual(AgentDropVersion.display, "v0.2.10 (12)")
    }
}
