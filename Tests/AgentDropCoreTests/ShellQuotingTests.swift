import XCTest
@testable import AgentDropCore

final class ShellQuotingTests: XCTestCase {
    func testSingleQuotesRemotePathFragments() {
        XCTAssertEqual(ShellQuoting.singleQuote("demo file.png"), "'demo file.png'")
        XCTAssertEqual(ShellQuoting.singleQuote("client's note.pdf"), "'client'\"'\"'s note.pdf'")
    }

    func testBuildsHomeRelativeCommandPath() {
        let commandPath = ShellQuoting.homeRelativeCommandPath(".agent-inbox/2026-06-15/demo file.png")

        XCTAssertEqual(commandPath, "$HOME/'.agent-inbox/2026-06-15/demo file.png'")
    }
}
