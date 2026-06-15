import XCTest
@testable import AgentDropCore

final class UploadServiceTests: XCTestCase {
    func testUploadsFileAndCopiesFinalRemotePath() throws {
        let file = URL(fileURLWithPath: "/tmp/demo.png")
        let runner = FakeCommandRunner(results: [
            .success(stdout: "", stderr: ""),
            .failure(exitCode: 1, stdout: "", stderr: ""),
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: "")
        ])
        let clipboard = FakeClipboard()
        let service = UploadService(runner: runner, clipboard: clipboard, clock: FixedClock(date: Date(timeIntervalSince1970: 1_781_510_400)))

        let uploaded = try service.upload(files: [file], target: SSHTarget(name: "devbox", source: .config))

        XCTAssertEqual(uploaded.map(\.remoteDisplayPath), ["~/.agent-inbox/2026-06-15/demo.png"])
        XCTAssertEqual(clipboard.text, "~/.agent-inbox/2026-06-15/demo.png")
        XCTAssertEqual(runner.invocations, [
            CommandInvocation(
                executable: "/usr/bin/ssh",
                arguments: ["devbox", "mkdir -p -- $HOME/'.agent-inbox/2026-06-15'"]
            ),
            CommandInvocation(
                executable: "/usr/bin/ssh",
                arguments: ["devbox", "test -e $HOME/'.agent-inbox/2026-06-15/demo.png'"]
            ),
            CommandInvocation(
                executable: "/usr/bin/rsync",
                arguments: ["-a", "/tmp/demo.png", "devbox:$HOME/'.agent-inbox/2026-06-15/demo.png'"]
            )
        ])
    }

    func testRenamesWhenRemoteFileExists() throws {
        let file = URL(fileURLWithPath: "/tmp/demo.png")
        let runner = FakeCommandRunner(results: [
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: ""),
            .failure(exitCode: 1, stdout: "", stderr: ""),
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: "")
        ])
        let clipboard = FakeClipboard()
        let service = UploadService(runner: runner, clipboard: clipboard, clock: FixedClock(date: Date(timeIntervalSince1970: 1_781_510_400)))

        let uploaded = try service.upload(files: [file], target: SSHTarget(name: "devbox", source: .config))

        XCTAssertEqual(uploaded.map(\.remoteDisplayPath), ["~/.agent-inbox/2026-06-15/demo-2.png"])
        XCTAssertEqual(clipboard.text, "~/.agent-inbox/2026-06-15/demo-2.png")
    }

    func testDoesNotWriteClipboardWhenUploadFails() {
        let file = URL(fileURLWithPath: "/tmp/demo.png")
        let runner = FakeCommandRunner(results: [
            .success(stdout: "", stderr: ""),
            .failure(exitCode: 1, stdout: "", stderr: ""),
            .failure(exitCode: 23, stdout: "", stderr: "rsync failed")
        ])
        let clipboard = FakeClipboard()
        let service = UploadService(runner: runner, clipboard: clipboard, clock: FixedClock(date: Date(timeIntervalSince1970: 1_781_510_400)))

        XCTAssertThrowsError(try service.upload(files: [file], target: SSHTarget(name: "devbox", source: .config)))
        XCTAssertNil(clipboard.text)
    }

    func testAbortsWhenRemoteExistenceCheckFails() {
        let file = URL(fileURLWithPath: "/tmp/demo.png")
        let runner = FakeCommandRunner(results: [
            .success(stdout: "", stderr: ""),
            .failure(exitCode: 255, stdout: "", stderr: "ssh failed"),
            .success(stdout: "", stderr: "")
        ])
        let clipboard = FakeClipboard()
        let service = UploadService(runner: runner, clipboard: clipboard, clock: FixedClock(date: Date(timeIntervalSince1970: 1_781_510_400)))

        XCTAssertThrowsError(try service.upload(files: [file], target: SSHTarget(name: "devbox", source: .config))) { error in
            XCTAssertEqual(error as? UploadError, .remoteExistenceCheckFailed("ssh failed"))
        }
        XCTAssertNil(clipboard.text)
        XCTAssertEqual(runner.invocations.map(\.executable), ["/usr/bin/ssh", "/usr/bin/ssh"])
    }
}

private final class FakeClipboard: ClipboardWriting {
    var text: String?
    func write(_ text: String) throws {
        self.text = text
    }
}

private final class FakeCommandRunner: CommandRunning {
    var results: [CommandResult]
    var invocations: [CommandInvocation] = []

    init(results: [CommandResult]) {
        self.results = results
    }

    func run(_ invocation: CommandInvocation) throws -> CommandResult {
        invocations.append(invocation)
        return results.removeFirst()
    }
}
