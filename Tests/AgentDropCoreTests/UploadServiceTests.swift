import XCTest
@testable import AgentDropCore

final class UploadServiceTests: XCTestCase {
    func testUploadsFileAndCopiesFinalRemotePath() throws {
        let file = URL(fileURLWithPath: "/tmp/demo.png")
        let runner = FakeCommandRunner(results: [
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: ""),
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
                arguments: ["devbox", "if ( set -C; : > $HOME/'.agent-inbox/2026-06-15/demo.png' ) 2>/dev/null; then exit 0; fi; test -e $HOME/'.agent-inbox/2026-06-15/demo.png' && exit 1; exit 2"]
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

    func testCanUploadWithoutWritingClipboard() throws {
        let file = URL(fileURLWithPath: "/tmp/demo.png")
        let runner = FakeCommandRunner(results: [
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: "")
        ])
        let clipboard = FakeClipboard()
        let service = UploadService(runner: runner, clipboard: clipboard, clock: FixedClock(date: Date(timeIntervalSince1970: 1_781_510_400)))

        let uploaded = try service.upload(files: [file], target: SSHTarget(name: "devbox", source: .config), copyToClipboard: false)

        XCTAssertEqual(uploaded.map(\.remoteDisplayPath), ["~/.agent-inbox/2026-06-15/demo.png"])
        XCTAssertNil(clipboard.text)
        XCTAssertEqual(runner.invocations.map(\.executable), ["/usr/bin/ssh", "/usr/bin/ssh", "/usr/bin/rsync"])
    }

    func testUploadsStagedSourceUsingOriginalRemoteName() throws {
        let source = UploadSourceFile(
            sourceURL: URL(fileURLWithPath: "/tmp/AgentDropUploads/fixed/0-demo.png"),
            remoteName: "demo.png"
        )
        let runner = FakeCommandRunner(results: [
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: "")
        ])
        let clipboard = FakeClipboard()
        let service = UploadService(runner: runner, clipboard: clipboard, clock: FixedClock(date: Date(timeIntervalSince1970: 1_781_510_400)))

        let uploaded = try service.upload(sources: [source], target: SSHTarget(name: "devbox", source: .config), copyToClipboard: false)

        XCTAssertEqual(uploaded.map(\.remoteDisplayPath), ["~/.agent-inbox/2026-06-15/demo.png"])
        XCTAssertEqual(runner.invocations[1].arguments[1], "if ( set -C; : > $HOME/'.agent-inbox/2026-06-15/demo.png' ) 2>/dev/null; then exit 0; fi; test -e $HOME/'.agent-inbox/2026-06-15/demo.png' && exit 1; exit 2")
        XCTAssertEqual(runner.invocations[2], CommandInvocation(
            executable: "/usr/bin/rsync",
            arguments: ["-a", "/tmp/AgentDropUploads/fixed/0-demo.png", "devbox:$HOME/'.agent-inbox/2026-06-15/demo.png'"]
        ))
    }

    func testUploadsStagedSourcePreservingOriginalDisplayName() throws {
        let source = UploadSourceFile(
            sourceURL: URL(fileURLWithPath: "/tmp/AgentDropUploads/fixed/0-demo.png"),
            remoteName: "demo.png"
        )
        let runner = FakeCommandRunner(results: [
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: "")
        ])
        let clipboard = FakeClipboard()
        let service = UploadService(runner: runner, clipboard: clipboard, clock: FixedClock(date: Date(timeIntervalSince1970: 1_781_510_400)))

        let uploaded = try service.upload(sources: [source], target: SSHTarget(name: "devbox", source: .config), copyToClipboard: false)

        XCTAssertEqual(uploaded.map(\.localDisplayName), ["demo.png"])
        XCTAssertEqual(uploaded.map(\.localURL.lastPathComponent), ["0-demo.png"])
    }

    func testUploadsStagedDirectoryUsingRemoteDirectoryReservation() throws {
        let source = UploadSourceFile(
            sourceURL: URL(fileURLWithPath: "/tmp/AgentDropUploads/fixed/0-assets", isDirectory: true),
            remoteName: "assets",
            isDirectory: true
        )
        let runner = FakeCommandRunner(results: [
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: "")
        ])
        let clipboard = FakeClipboard()
        let service = UploadService(runner: runner, clipboard: clipboard, clock: FixedClock(date: Date(timeIntervalSince1970: 1_781_510_400)))

        let uploaded = try service.upload(sources: [source], target: SSHTarget(name: "devbox", source: .config), copyToClipboard: false)

        XCTAssertEqual(uploaded.map(\.remoteDisplayPath), ["~/.agent-inbox/2026-06-15/assets"])
        XCTAssertEqual(uploaded.map(\.localDisplayName), ["assets"])
        XCTAssertEqual(runner.invocations[1], CommandInvocation(
            executable: "/usr/bin/ssh",
            arguments: ["devbox", "if mkdir $HOME/'.agent-inbox/2026-06-15/assets' 2>/dev/null; then exit 0; fi; test -e $HOME/'.agent-inbox/2026-06-15/assets' && exit 1; exit 2"]
        ))
        XCTAssertEqual(runner.invocations[2], CommandInvocation(
            executable: "/usr/bin/rsync",
            arguments: ["-a", "/tmp/AgentDropUploads/fixed/0-assets/", "devbox:$HOME/'.agent-inbox/2026-06-15/assets'/"]
        ))
    }

    func testUploadsDirectoryURLUsingRemoteDirectoryReservation() throws {
        let root = try makeUploadServiceTemporaryDirectory()
        let directory = root.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let runner = FakeCommandRunner(results: [
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: "")
        ])
        let clipboard = FakeClipboard()
        let service = UploadService(runner: runner, clipboard: clipboard, clock: FixedClock(date: Date(timeIntervalSince1970: 1_781_510_400)))

        let uploaded = try service.upload(files: [directory], target: SSHTarget(name: "devbox", source: .config), copyToClipboard: false)

        XCTAssertEqual(uploaded.map(\.remoteDisplayPath), ["~/.agent-inbox/2026-06-15/assets"])
        XCTAssertEqual(runner.invocations[1], CommandInvocation(
            executable: "/usr/bin/ssh",
            arguments: ["devbox", "if mkdir $HOME/'.agent-inbox/2026-06-15/assets' 2>/dev/null; then exit 0; fi; test -e $HOME/'.agent-inbox/2026-06-15/assets' && exit 1; exit 2"]
        ))
        XCTAssertEqual(runner.invocations[2], CommandInvocation(
            executable: "/usr/bin/rsync",
            arguments: ["-a", directory.path + "/", "devbox:$HOME/'.agent-inbox/2026-06-15/assets'/"]
        ))
    }

    func testDoesNotWriteClipboardWhenUploadFails() {
        let file = URL(fileURLWithPath: "/tmp/demo.png")
        let runner = FakeCommandRunner(results: [
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: ""),
            .failure(exitCode: 23, stdout: "", stderr: "rsync failed"),
            .success(stdout: "", stderr: "")
        ])
        let clipboard = FakeClipboard()
        let service = UploadService(runner: runner, clipboard: clipboard, clock: FixedClock(date: Date(timeIntervalSince1970: 1_781_510_400)))

        XCTAssertThrowsError(try service.upload(files: [file], target: SSHTarget(name: "devbox", source: .config)))
        XCTAssertNil(clipboard.text)
    }

    func testClipboardFailurePreservesReason() {
        let file = URL(fileURLWithPath: "/tmp/demo.png")
        let runner = FakeCommandRunner(results: [
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: "")
        ])
        let clipboard = FakeClipboard(error: ClipboardError.writeFailed("pasteboard unavailable"))
        let service = UploadService(runner: runner, clipboard: clipboard, clock: FixedClock(date: Date(timeIntervalSince1970: 1_781_510_400)))

        XCTAssertThrowsError(try service.upload(files: [file], target: SSHTarget(name: "devbox", source: .config))) { error in
            XCTAssertEqual(error as? UploadError, .clipboardFailed("pasteboard unavailable"))
        }
    }

    func testRemovesReservedRemoteNameWhenRsyncFails() {
        let file = URL(fileURLWithPath: "/tmp/demo.png")
        let runner = FakeCommandRunner(results: [
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: ""),
            .failure(exitCode: 23, stdout: "", stderr: "rsync failed"),
            .success(stdout: "", stderr: "")
        ])
        let clipboard = FakeClipboard()
        let service = UploadService(runner: runner, clipboard: clipboard, clock: FixedClock(date: Date(timeIntervalSince1970: 1_781_510_400)))

        XCTAssertThrowsError(try service.upload(files: [file], target: SSHTarget(name: "devbox", source: .config))) { error in
            XCTAssertEqual(error as? UploadError, .rsyncFailed("rsync failed"))
        }

        XCTAssertEqual(runner.invocations.last, CommandInvocation(
            executable: "/usr/bin/ssh",
            arguments: ["devbox", "rm -f -- $HOME/'.agent-inbox/2026-06-15/demo.png'"]
        ))
        XCTAssertNil(clipboard.text)
    }

    func testRemovesReservedRemoteDirectoryWhenDirectoryRsyncFails() {
        let source = UploadSourceFile(
            sourceURL: URL(fileURLWithPath: "/tmp/AgentDropUploads/fixed/0-assets", isDirectory: true),
            remoteName: "assets",
            isDirectory: true
        )
        let runner = FakeCommandRunner(results: [
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: ""),
            .failure(exitCode: 23, stdout: "", stderr: "rsync failed"),
            .success(stdout: "", stderr: "")
        ])
        let clipboard = FakeClipboard()
        let service = UploadService(runner: runner, clipboard: clipboard, clock: FixedClock(date: Date(timeIntervalSince1970: 1_781_510_400)))

        XCTAssertThrowsError(try service.upload(sources: [source], target: SSHTarget(name: "devbox", source: .config))) { error in
            XCTAssertEqual(error as? UploadError, .rsyncFailed("rsync failed"))
        }

        XCTAssertEqual(runner.invocations.last, CommandInvocation(
            executable: "/usr/bin/ssh",
            arguments: ["devbox", "rm -rf -- $HOME/'.agent-inbox/2026-06-15/assets'"]
        ))
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

    func testTreatsReservationMissAsConflictAndTriesNextCandidate() throws {
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

        XCTAssertEqual(uploaded.map(\.remoteDisplayPath), ["~/.agent-inbox/2026-06-15/demo-2.png"])
        XCTAssertEqual(runner.invocations[1].arguments[1], "if ( set -C; : > $HOME/'.agent-inbox/2026-06-15/demo.png' ) 2>/dev/null; then exit 0; fi; test -e $HOME/'.agent-inbox/2026-06-15/demo.png' && exit 1; exit 2")
        XCTAssertEqual(runner.invocations[2].arguments[1], "if ( set -C; : > $HOME/'.agent-inbox/2026-06-15/demo-2.png' ) 2>/dev/null; then exit 0; fi; test -e $HOME/'.agent-inbox/2026-06-15/demo-2.png' && exit 1; exit 2")
    }
}

private final class FakeClipboard: ClipboardWriting {
    var text: String?
    var error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func write(_ text: String) throws {
        if let error {
            throw error
        }
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

private func makeUploadServiceTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
