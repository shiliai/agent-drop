import XCTest
@testable import AgentDropCore

final class RemoteNamePlannerTests: XCTestCase {
    func testCandidateNamesForFileWithExtension() {
        let planner = RemoteNamePlanner(originalName: "demo.png")

        XCTAssertEqual(Array(planner.candidates(prefixCount: 4)), ["demo.png", "demo-2.png", "demo-3.png", "demo-4.png"])
    }

    func testCandidateNamesForFileWithoutExtension() {
        let planner = RemoteNamePlanner(originalName: "README")

        XCTAssertEqual(Array(planner.candidates(prefixCount: 3)), ["README", "README-2", "README-3"])
    }

    func testCandidateNamesForDotfile() {
        let planner = RemoteNamePlanner(originalName: ".env")

        XCTAssertEqual(Array(planner.candidates(prefixCount: 3)), [".env", ".env-2", ".env-3"])
    }
}
