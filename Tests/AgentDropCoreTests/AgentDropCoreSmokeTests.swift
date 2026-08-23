import XCTest
@testable import AgentDropCore

final class AgentDropCoreSmokeTests: XCTestCase {
    func testVersionConstantIsAvailable() {
        XCTAssertEqual(AgentDropVersion.current, "0.2.5")
        XCTAssertEqual(AgentDropVersion.build, "6")
        XCTAssertEqual(AgentDropVersion.display, "v0.2.5 (6)")
    }
}
