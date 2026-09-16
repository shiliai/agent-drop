import XCTest
@testable import AgentDropCore

final class AgentDropCoreSmokeTests: XCTestCase {
    func testVersionConstantIsAvailable() {
        XCTAssertEqual(AgentDropVersion.current, "0.2.6")
        XCTAssertEqual(AgentDropVersion.build, "7")
        XCTAssertEqual(AgentDropVersion.display, "v0.2.6 (7)")
    }
}
