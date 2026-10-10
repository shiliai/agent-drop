import XCTest
@testable import AgentDropCore

final class AgentDropCoreSmokeTests: XCTestCase {
    func testVersionConstantIsAvailable() {
        XCTAssertEqual(AgentDropVersion.current, "0.2.9")
        XCTAssertEqual(AgentDropVersion.build, "10")
        XCTAssertEqual(AgentDropVersion.display, "v0.2.9 (10)")
    }
}
