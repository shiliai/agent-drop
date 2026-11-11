import XCTest
@testable import AgentDropCore

final class AgentDropCoreSmokeTests: XCTestCase {
    func testVersionConstantIsAvailable() {
        XCTAssertEqual(AgentDropVersion.current, "0.2.13")
        XCTAssertEqual(AgentDropVersion.build, "15")
        XCTAssertEqual(AgentDropVersion.display, "v0.2.13 (15)")
    }
}
