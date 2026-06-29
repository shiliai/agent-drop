import XCTest
@testable import AgentDropCore

final class AgentDropCoreSmokeTests: XCTestCase {
    func testVersionConstantIsAvailable() {
        XCTAssertEqual(AgentDropVersion.current, "0.2.3")
        XCTAssertEqual(AgentDropVersion.build, "4")
        XCTAssertEqual(AgentDropVersion.display, "v0.2.3 (4)")
    }
}
