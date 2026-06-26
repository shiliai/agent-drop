import XCTest
@testable import AgentDropCore

final class DownloadServiceTests: XCTestCase {
    func testFailsWhenRemotePathListIsEmpty() {
        let service = DownloadService(
            runner: FakeDownloadCommandRunner(results: []),
            pipelineRunner: FakeDownloadPipelineRunner(results: []),
            clipboard: FakeDownloadClipboard()
        )

        XCTAssertThrowsError(try service.download(remotePaths: [], target: target, destinationRoot: URL(fileURLWithPath: "/tmp"))) { error in
            XCTAssertEqual(error as? DownloadError, .noRemotePaths)
        }
    }

    func testDownloadsRegularFileAndCopiesFinalLocalPath() throws {
        let root = try makeDownloadTemporaryDirectory()
        let runner = FakeDownloadCommandRunner(results: [
            .success(stdout: "file\n", stderr: ""),
            .success(stdout: "", stderr: "")
        ])
        let clipboard = FakeDownloadClipboard()
        let service = DownloadService(
            runner: runner,
            pipelineRunner: FakeDownloadPipelineRunner(results: []),
            clipboard: clipboard
        )

        let downloaded = try service.download(
            remotePaths: [RemotePath(hostHint: nil, path: "~/runs/output.png")],
            target: target,
            destinationRoot: root
        )

        let expectedURL = root.appendingPathComponent("output.png")
        XCTAssertEqual(downloaded, [
            DownloadedFile(
                remotePath: "~/runs/output.png",
                localURL: expectedURL,
                localDisplayPath: expectedURL.path,
                strategy: .rsyncFile
            )
        ])
        XCTAssertEqual(clipboard.text, expectedURL.path)
        XCTAssertEqual(runner.invocations, [
            DownloadTransferPlanner.remoteInspectionCommand(target: target, remotePath: "~/runs/output.png"),
            CommandInvocation(
                executable: "/usr/bin/rsync",
                arguments: ["-a", "devbox:$HOME/'runs/output.png'", expectedURL.path]
            )
        ])
    }

    func testRepeatedPullUsesNonOverwritingLocalName() throws {
        let root = try makeDownloadTemporaryDirectory()
        FileManager.default.createFile(atPath: root.appendingPathComponent("output.png").path, contents: Data())
        let runner = FakeDownloadCommandRunner(results: [
            .success(stdout: "file\n", stderr: ""),
            .success(stdout: "", stderr: "")
        ])
        let service = DownloadService(
            runner: runner,
            pipelineRunner: FakeDownloadPipelineRunner(results: []),
            clipboard: FakeDownloadClipboard()
        )

        let downloaded = try service.download(
            remotePaths: [RemotePath(hostHint: nil, path: "~/runs/output.png")],
            target: target,
            destinationRoot: root,
            copyToClipboard: false
        )

        XCTAssertEqual(downloaded.map(\.localURL.lastPathComponent), ["output-2.png"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("output.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("output-2.png").path))
    }

    func testSmallDirectoryUsesRsyncDirectory() throws {
        let root = try makeDownloadTemporaryDirectory()
        let runner = FakeDownloadCommandRunner(results: [
            .success(stdout: "directory\n200\n", stderr: ""),
            .success(stdout: "", stderr: "")
        ])
        let service = DownloadService(
            runner: runner,
            pipelineRunner: FakeDownloadPipelineRunner(results: []),
            clipboard: FakeDownloadClipboard()
        )

        let downloaded = try service.download(
            remotePaths: [RemotePath(hostHint: nil, path: "/tmp/build-artifacts")],
            target: target,
            destinationRoot: root,
            copyToClipboard: false
        )

        let expectedURL = root.appendingPathComponent("build-artifacts", isDirectory: true)
        XCTAssertEqual(downloaded.map(\.strategy), [.rsyncDirectory])
        XCTAssertEqual(downloaded.map(\.localDisplayPath), [expectedURL.path])
        XCTAssertEqual(runner.invocations.last, CommandInvocation(
            executable: "/usr/bin/rsync",
            arguments: ["-a", "devbox:'/tmp/build-artifacts'/", expectedURL.path + "/"]
        ))
    }

    func testLargeDirectoryUsesTarPipelineAndAutoExtractedReservedDirectoryPath() throws {
        let root = try makeDownloadTemporaryDirectory()
        let runner = FakeDownloadCommandRunner(results: [
            .success(stdout: "directory\n201\n", stderr: "")
        ])
        let pipelineRunner = FakeDownloadPipelineRunner(results: [
            .success(stdout: "", stderr: "")
        ])
        let service = DownloadService(
            runner: runner,
            pipelineRunner: pipelineRunner,
            clipboard: FakeDownloadClipboard()
        )

        let downloaded = try service.download(
            remotePaths: [RemotePath(hostHint: nil, path: "/tmp/client's reports")],
            target: target,
            destinationRoot: root,
            copyToClipboard: false
        )

        let expectedURL = root.appendingPathComponent("client's reports", isDirectory: true)
        XCTAssertEqual(downloaded.map(\.strategy), [.tarStream])
        XCTAssertEqual(downloaded.map(\.localURL), [expectedURL])
        XCTAssertEqual(pipelineRunner.pipelines, [
            DownloadPipelineInvocation(
                stdoutOf: CommandInvocation(
                    executable: "/usr/bin/ssh",
                    arguments: ["devbox", "tar -C '/tmp/client'\"'\"'s reports' -czf - ."]
                ),
                intoStdinOf: CommandInvocation(
                    executable: "/usr/bin/tar",
                    arguments: ["-xzf", "-", "-C", expectedURL.path]
                )
            )
        ])
        XCTAssertEqual(runner.invocations, [
            DownloadTransferPlanner.remoteInspectionCommand(target: target, remotePath: "/tmp/client's reports")
        ])
    }

    func testRemoteMissingInspectionFailureDoesNotWriteClipboard() throws {
        let root = try makeDownloadTemporaryDirectory()
        let clipboard = FakeDownloadClipboard()
        let service = DownloadService(
            runner: FakeDownloadCommandRunner(results: [
                .failure(exitCode: 2, stdout: "", stderr: "not found")
            ]),
            pipelineRunner: FakeDownloadPipelineRunner(results: []),
            clipboard: clipboard
        )

        XCTAssertThrowsError(try service.download(
            remotePaths: [RemotePath(hostHint: nil, path: "~/runs/missing.png")],
            target: target,
            destinationRoot: root
        )) { error in
            XCTAssertEqual(error as? DownloadError, .remoteInspectionFailed("not found"))
        }
        XCTAssertNil(clipboard.text)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testUnrecognizedInspectionStdoutFailsAndCleansReservation() throws {
        let root = try makeDownloadTemporaryDirectory()
        let clipboard = FakeDownloadClipboard()
        let service = DownloadService(
            runner: FakeDownloadCommandRunner(results: [
                .success(stdout: "symlink\n", stderr: "")
            ]),
            pipelineRunner: FakeDownloadPipelineRunner(results: []),
            clipboard: clipboard
        )

        XCTAssertThrowsError(try service.download(
            remotePaths: [RemotePath(hostHint: nil, path: "~/runs/output.png")],
            target: target,
            destinationRoot: root
        )) { error in
            XCTAssertEqual(error as? DownloadError, .remoteInspectionFailed("symlink\n"))
        }
        XCTAssertNil(clipboard.text)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testRsyncFailureRemovesReservedOutputAndDoesNotWriteClipboard() throws {
        let root = try makeDownloadTemporaryDirectory()
        let clipboard = FakeDownloadClipboard()
        let service = DownloadService(
            runner: FakeDownloadCommandRunner(results: [
                .success(stdout: "file\n", stderr: ""),
                .failure(exitCode: 23, stdout: "", stderr: "rsync failed")
            ]),
            pipelineRunner: FakeDownloadPipelineRunner(results: []),
            clipboard: clipboard
        )

        XCTAssertThrowsError(try service.download(
            remotePaths: [RemotePath(hostHint: nil, path: "~/runs/output.png")],
            target: target,
            destinationRoot: root
        )) { error in
            XCTAssertEqual(error as? DownloadError, .rsyncFailed("rsync failed"))
        }
        XCTAssertNil(clipboard.text)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("output.png").path))
    }

    func testTarPipelineFailureRemovesReservedDirectoryAndDoesNotWriteClipboard() throws {
        let root = try makeDownloadTemporaryDirectory()
        let clipboard = FakeDownloadClipboard()
        let service = DownloadService(
            runner: FakeDownloadCommandRunner(results: [
                .success(stdout: "directory\n201\n", stderr: "")
            ]),
            pipelineRunner: FakeDownloadPipelineRunner(results: [
                .failure(exitCode: 2, stdout: "", stderr: "tar failed")
            ]),
            clipboard: clipboard
        )

        XCTAssertThrowsError(try service.download(
            remotePaths: [RemotePath(hostHint: nil, path: "/tmp/artifacts")],
            target: target,
            destinationRoot: root
        )) { error in
            XCTAssertEqual(error as? DownloadError, .tarFailed("tar failed"))
        }
        XCTAssertNil(clipboard.text)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("artifacts", isDirectory: true).path))
    }

    func testClipboardFailureAfterTransferPreservesDownloadedOutput() throws {
        let root = try makeDownloadTemporaryDirectory()
        let service = DownloadService(
            runner: FakeDownloadCommandRunner(results: [
                .success(stdout: "file\n", stderr: ""),
                .success(stdout: "", stderr: "")
            ]),
            pipelineRunner: FakeDownloadPipelineRunner(results: []),
            clipboard: FakeDownloadClipboard(error: ClipboardError.writeFailed("pasteboard unavailable"))
        )

        XCTAssertThrowsError(try service.download(
            remotePaths: [RemotePath(hostHint: nil, path: "~/runs/output.png")],
            target: target,
            destinationRoot: root
        )) { error in
            XCTAssertEqual(error as? DownloadError, .clipboardFailed("pasteboard unavailable"))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("output.png").path))
    }

    func testCanDownloadWithoutWritingClipboard() throws {
        let root = try makeDownloadTemporaryDirectory()
        let clipboard = FakeDownloadClipboard()
        let service = DownloadService(
            runner: FakeDownloadCommandRunner(results: [
                .success(stdout: "file\n", stderr: ""),
                .success(stdout: "", stderr: "")
            ]),
            pipelineRunner: FakeDownloadPipelineRunner(results: []),
            clipboard: clipboard
        )

        _ = try service.download(
            remotePaths: [RemotePath(hostHint: nil, path: "~/runs/output.png")],
            target: target,
            destinationRoot: root,
            copyToClipboard: false
        )

        XCTAssertNil(clipboard.text)
    }

    func testAllOrNothingClipboardWhenLaterPathFails() throws {
        let root = try makeDownloadTemporaryDirectory()
        let clipboard = FakeDownloadClipboard()
        let service = DownloadService(
            runner: FakeDownloadCommandRunner(results: [
                .success(stdout: "file\n", stderr: ""),
                .success(stdout: "", stderr: ""),
                .failure(exitCode: 2, stdout: "", stderr: "missing")
            ]),
            pipelineRunner: FakeDownloadPipelineRunner(results: []),
            clipboard: clipboard
        )

        XCTAssertThrowsError(try service.download(
            remotePaths: [
                RemotePath(hostHint: nil, path: "~/runs/first.png"),
                RemotePath(hostHint: nil, path: "~/runs/second.png")
            ],
            target: target,
            destinationRoot: root
        )) { error in
            XCTAssertEqual(error as? DownloadError, .remoteInspectionFailed("missing"))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("first.png").path))
        XCTAssertNil(clipboard.text)
    }

    private var target: SSHTarget {
        SSHTarget(name: "devbox", source: .config)
    }
}

private final class FakeDownloadClipboard: ClipboardWriting {
    var text: String?
    private let error: Error?

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

private final class FakeDownloadCommandRunner: CommandRunning {
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

private final class FakeDownloadPipelineRunner: CommandPiping {
    var results: [CommandResult]
    var pipelines: [DownloadPipelineInvocation] = []

    init(results: [CommandResult]) {
        self.results = results
    }

    func runPipeline(stdoutOf producer: CommandInvocation, intoStdinOf consumer: CommandInvocation) throws -> CommandResult {
        pipelines.append(DownloadPipelineInvocation(stdoutOf: producer, intoStdinOf: consumer))
        return results.removeFirst()
    }
}

private struct DownloadPipelineInvocation: Equatable {
    let stdoutOf: CommandInvocation
    let intoStdinOf: CommandInvocation
}

private func makeDownloadTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
