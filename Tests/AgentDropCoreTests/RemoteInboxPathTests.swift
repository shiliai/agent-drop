import XCTest
@testable import AgentDropCore

final class RemoteInboxPathTests: XCTestCase {
    func testUsesDateFolderForDisplayPath() {
        let date = Date(timeIntervalSince1970: 1_781_510_400)
        let clock = FixedClock(date: date)
        let path = RemoteInboxPath(clock: clock)

        XCTAssertEqual(path.dateFolder, "2026-06-15")
        XCTAssertEqual(path.displayDirectory, "~/.agent-inbox/2026-06-15/")
    }

    func testFormatsDisplayFilePath() {
        let path = RemoteInboxPath(clock: FixedClock(date: Date(timeIntervalSince1970: 1_781_510_400)))

        XCTAssertEqual(path.displayPath(forRemoteName: "demo.png"), "~/.agent-inbox/2026-06-15/demo.png")
    }
}
