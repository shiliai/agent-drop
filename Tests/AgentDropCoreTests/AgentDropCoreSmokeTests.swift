import XCTest
@testable import AgentDropCore

final class AgentDropCoreSmokeTests: XCTestCase {
    func testVersionConstantIsAvailable() {
        XCTAssertEqual(AgentDropVersion.current, "0.2.2")
        XCTAssertEqual(AgentDropVersion.build, "3")
        XCTAssertEqual(AgentDropVersion.display, "v0.2.2 (3)")
    }
}
