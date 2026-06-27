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

    func testParsesPullWithExplicitTargetAndMultiplePaths() throws {
        XCTAssertEqual(
            try CLIParser.parse(["pull", "--target", "devbox", "~/runs/output.png", "/tmp/build.log"]),
            .pull(target: "devbox", paths: ["~/runs/output.png", "/tmp/build.log"])
        )
    }

    func testParsesPullWithoutTarget() throws {
        XCTAssertEqual(
            try CLIParser.parse(["pull", "~/runs/output.png"]),
            .pull(target: nil, paths: ["~/runs/output.png"])
        )
    }

    func testRejectsPullWithoutPaths() {
        XCTAssertThrowsError(try CLIParser.parse(["pull", "--target", "devbox"])) { error in
            XCTAssertEqual(error as? CLIParseError, .missingFiles)
        }
    }

    func testRejectsPullMissingTargetValue() {
        XCTAssertThrowsError(try CLIParser.parse(["pull", "--target"])) { error in
            XCTAssertEqual(error as? CLIParseError, .missingTargetValue)
        }
    }

    func testRejectsSendWithoutFiles() {
        XCTAssertThrowsError(try CLIParser.parse(["send", "--target", "devbox"]))
    }
}
