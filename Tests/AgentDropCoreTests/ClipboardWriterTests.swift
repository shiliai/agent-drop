import XCTest
@testable import AgentDropCore

final class ClipboardWriterTests: XCTestCase {
    func testWritesTextToPbcopyStandardInput() throws {
        let runner = FakeClipboardCommandRunner(result: .success(stdout: "", stderr: ""))
        let writer = PBClipboardWriter(runner: runner)

        try writer.write("~/.agent-inbox/2026-06-15/demo.png")

        XCTAssertEqual(runner.invocations, [
            CommandInvocation(
                executable: "/usr/bin/pbcopy",
                arguments: [],
                standardInput: "~/.agent-inbox/2026-06-15/demo.png"
            )
        ])
    }
}

private final class FakeClipboardCommandRunner: CommandRunning {
    let result: CommandResult
    var invocations: [CommandInvocation] = []

    init(result: CommandResult) {
        self.result = result
    }

    func run(_ invocation: CommandInvocation) throws -> CommandResult {
        invocations.append(invocation)
        return result
    }
}
