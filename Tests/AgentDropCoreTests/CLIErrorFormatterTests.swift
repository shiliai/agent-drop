import XCTest
@testable import AgentDropCore

final class CLIErrorFormatterTests: XCTestCase {
    func testFormatsCLIParseErrorsWithClearMessages() {
        XCTAssertEqual(CLIErrorFormatter.message(for: CLIParseError.empty), "No command provided.")
        XCTAssertEqual(CLIErrorFormatter.message(for: CLIParseError.unknownCommand("foo")), "Unknown command 'foo'.")
        XCTAssertEqual(CLIErrorFormatter.message(for: CLIParseError.missingTargetValue), "Missing value after --target.")
        XCTAssertEqual(CLIErrorFormatter.message(for: CLIParseError.missingFiles), "No paths provided.")
    }

    func testFormatsRemotePathAndDownloadErrorsWithClearMessages() {
        XCTAssertEqual(
            CLIErrorFormatter.message(for: RemotePathParserError.unsupportedRelativePath("runs/output.png")),
            "Unsupported remote path 'runs/output.png'. Use ~/path or /absolute/path."
        )

        XCTAssertEqual(
            CLIErrorFormatter.message(for: DownloadError.hostHintMismatch(hostHint: "gpu-box", selectedTarget: "devbox")),
            "Remote path host 'gpu-box' does not match selected target 'devbox'."
        )
    }
}
