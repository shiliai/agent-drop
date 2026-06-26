import XCTest
@testable import AgentDropCore

final class LocalNamePlannerTests: XCTestCase {
    func testCandidateNamesMatchUploadPatternForExtensionsExtensionlessDotfilesAndDirectories() {
        XCTAssertEqual(
            Array(LocalNamePlanner(originalName: "output.png").candidates(prefixCount: 3)),
            ["output.png", "output-2.png", "output-3.png"]
        )
        XCTAssertEqual(
            Array(LocalNamePlanner(originalName: "build-artifacts").candidates(prefixCount: 3)),
            ["build-artifacts", "build-artifacts-2", "build-artifacts-3"]
        )
        XCTAssertEqual(
            Array(LocalNamePlanner(originalName: ".env").candidates(prefixCount: 3)),
            [".env", ".env-2", ".env-3"]
        )
        XCTAssertEqual(
            Array(LocalNamePlanner(originalName: ".profile.backup").candidates(prefixCount: 3)),
            [".profile.backup", ".profile-2.backup", ".profile-3.backup"]
        )
    }
}
