import XCTest
@testable import AgentDropCore

final class AgentDropCoreSmokeTests: XCTestCase {
    func testVersionConstantIsAvailable() {
        XCTAssertEqual(AgentDropVersion.current, "0.2.11")
        XCTAssertEqual(AgentDropVersion.build, "13")
        XCTAssertEqual(AgentDropVersion.display, "v0.2.11 (13)")
    }
}
