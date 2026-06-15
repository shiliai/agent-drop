import XCTest
@testable import AgentDropCore

final class CLIParserTests: XCTestCase {
    func testParsesTargetsCommand() throws {
        XCTAssertEqual(try CLIParser.parse(["targets"]), .targets)
    }

    func testParsesDoctorCommand() throws {
        XCTAssertEqual(try CLIParser.parse(["doctor"]), .doctor)
    }

    func testParsesSendWithExplicitTarget() throws {
        XCTAssertEqual(
            try CLIParser.parse(["send", "--target", "devbox", "/tmp/demo.png"]),
            .send(target: "devbox", paths: ["/tmp/demo.png"])
        )
    }

    func testRejectsSendWithoutFiles() {
        XCTAssertThrowsError(try CLIParser.parse(["send", "--target", "devbox"]))
    }
}
