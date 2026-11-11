import XCTest
@testable import AgentDropCore

final class AgentDropCoreSmokeTests: XCTestCase {
    func testVersionConstantIsAvailable() {
        XCTAssertEqual(AgentDropVersion.current, "0.2.12")
        XCTAssertEqual(AgentDropVersion.build, "14")
        XCTAssertEqual(AgentDropVersion.display, "v0.2.12 (14)")
    }
}
