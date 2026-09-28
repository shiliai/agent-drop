import XCTest
@testable import AgentDropCore

final class AgentDropCoreSmokeTests: XCTestCase {
    func testVersionConstantIsAvailable() {
        XCTAssertEqual(AgentDropVersion.current, "0.2.7")
        XCTAssertEqual(AgentDropVersion.build, "8")
        XCTAssertEqual(AgentDropVersion.display, "v0.2.7 (8)")
    }
}
