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

    func testMatchingHostHintByTargetNameProceedsNormally() throws {
        let root = try makeDownloadTemporaryDirectory()
        let target = SSHTarget(name: "GPU Box", connectName: "gpu-box.internal", source: .config)
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
            remotePaths: [RemotePath(hostHint: "GPU Box", path: "~/runs/output.png")],
            target: target,
            destinationRoot: root,
            copyToClipboard: false
        )

        XCTAssertEqual(downloaded.map(\.remotePath), ["~/runs/output.png"])
        XCTAssertEqual(runner.invocations.first, DownloadTransferPlanner.remoteInspectionCommand(target: target, remotePath: "~/runs/output.png"))
    }

    func testMatchingHostHintByTargetConnectNameProceedsNormally() throws {
        let root = try makeDownloadTemporaryDirectory()
        let target = SSHTarget(name: "GPU Box", connectName: "gpu-box.internal", source: .config)
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
            remotePaths: [RemotePath(hostHint: "gpu-box.internal", path: "~/runs/output.png")],
            target: target,
            destinationRoot: root,
            copyToClipboard: false
        )

        XCTAssertEqual(downloaded.map(\.remotePath), ["~/runs/output.png"])
        XCTAssertEqual(runner.invocations.first, DownloadTransferPlanner.remoteInspectionCommand(target: target, remotePath: "~/runs/output.png"))
    }

    func testHostHintMismatchFailsBeforeInspectionTransferOrClipboard() throws {
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

        XCTAssertThrowsError(try service.download(
            remotePaths: [RemotePath(hostHint: "gpu-box", path: "~/runs/output.png")],
            target: target,
            destinationRoot: root
        )) { error in
            XCTAssertEqual(error as? DownloadError, .hostHintMismatch(hostHint: "gpu-box", selectedTarget: "devbox"))
        }
        XCTAssertEqual(runner.invocations, [])
        XCTAssertNil(clipboard.text)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testUnsupportedRemotePathFailsBeforeInspectionTransferOrClipboard() throws {
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

        XCTAssertThrowsError(try service.download(
            remotePaths: [RemotePath(hostHint: nil, path: "relative/output.png")],
            target: target,
            destinationRoot: root
        )) { error in
            XCTAssertEqual(error as? DownloadError, .unsupportedRemotePath("relative/output.png"))
        }
        XCTAssertEqual(runner.invocations, [])
        XCTAssertNil(clipboard.text)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
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
            XCTAssertEqual(error as? DownloadError, .remoteInspectionFailed("target devbox remote path ~/runs/missing.png inspection failed with exit code 2: not found"))
        }
        XCTAssertNil(clipboard.text)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testRemoteInspectionFailureUsesStdoutFallbackWhenStderrIsEmpty() throws {
        let root = try makeDownloadTemporaryDirectory()
        let service = DownloadService(
            runner: FakeDownloadCommandRunner(results: [
                .failure(exitCode: 2, stdout: "missing from stdout", stderr: "")
            ]),
            pipelineRunner: FakeDownloadPipelineRunner(results: []),
            clipboard: FakeDownloadClipboard()
        )

        XCTAssertThrowsError(try service.download(
            remotePaths: [RemotePath(hostHint: nil, path: "~/runs/missing.png")],
            target: target,
            destinationRoot: root
        )) { error in
            XCTAssertEqual(error as? DownloadError, .remoteInspectionFailed("target devbox remote path ~/runs/missing.png inspection failed with exit code 2: missing from stdout"))
        }
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
            XCTAssertEqual(error as? DownloadError, .remoteInspectionFailed("target devbox remote path ~/runs/output.png inspection produced unrecognized output: symlink"))
        }
        XCTAssertNil(clipboard.text)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testInvalidDirectoryInspectionCountsFailAndDoNotWriteClipboardOrLeaveOutputs() throws {
        for (stdout, label) in [
            ("directory\nabc\n", "abc"),
            ("directory\n-1\n", "-1")
        ] {
            let root = try makeDownloadTemporaryDirectory()
            let clipboard = FakeDownloadClipboard()
            let service = DownloadService(
                runner: FakeDownloadCommandRunner(results: [
                    .success(stdout: stdout, stderr: "")
                ]),
                pipelineRunner: FakeDownloadPipelineRunner(results: []),
                clipboard: clipboard
            )

            XCTAssertThrowsError(try service.download(
                remotePaths: [RemotePath(hostHint: nil, path: "~/runs/artifacts")],
                target: target,
                destinationRoot: root
            )) { error in
                XCTAssertEqual(error as? DownloadError, .remoteInspectionFailed("target devbox remote path ~/runs/artifacts inspection produced unrecognized output: directory\n\(label)"))
            }
            XCTAssertNil(clipboard.text)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
        }
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
            XCTAssertEqual(error as? DownloadError, .rsyncFailed("target devbox remote path ~/runs/output.png transfer failed with exit code 23 using /usr/bin/rsync: rsync failed"))
        }
        XCTAssertNil(clipboard.text)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("output.png").path))
    }

    func testRsyncFailureUsesStdoutFallbackWhenStderrIsEmpty() throws {
        let root = try makeDownloadTemporaryDirectory()
        let service = DownloadService(
            runner: FakeDownloadCommandRunner(results: [
                .success(stdout: "file\n", stderr: ""),
                .failure(exitCode: 23, stdout: "rsync stdout failure", stderr: "")
            ]),
            pipelineRunner: FakeDownloadPipelineRunner(results: []),
            clipboard: FakeDownloadClipboard()
        )

        XCTAssertThrowsError(try service.download(
            remotePaths: [RemotePath(hostHint: nil, path: "~/runs/output.png")],
            target: target,
            destinationRoot: root
        )) { error in
            XCTAssertEqual(error as? DownloadError, .rsyncFailed("target devbox remote path ~/runs/output.png transfer failed with exit code 23 using /usr/bin/rsync: rsync stdout failure"))
        }
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
            XCTAssertEqual(error as? DownloadError, .tarFailed("target devbox remote path /tmp/artifacts tar pipeline failed with exit code 2 using /usr/bin/ssh | /usr/bin/tar: tar failed"))
        }
        XCTAssertNil(clipboard.text)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("artifacts", isDirectory: true).path))
    }

    func testTarFailureUsesStdoutFallbackWhenStderrIsEmpty() throws {
        let root = try makeDownloadTemporaryDirectory()
        let service = DownloadService(
            runner: FakeDownloadCommandRunner(results: [
                .success(stdout: "directory\n201\n", stderr: "")
            ]),
            pipelineRunner: FakeDownloadPipelineRunner(results: [
                .failure(exitCode: 2, stdout: "tar stdout failure", stderr: "")
            ]),
            clipboard: FakeDownloadClipboard()
        )

        XCTAssertThrowsError(try service.download(
            remotePaths: [RemotePath(hostHint: nil, path: "/tmp/artifacts")],
            target: target,
            destinationRoot: root
        )) { error in
            XCTAssertEqual(error as? DownloadError, .tarFailed("target devbox remote path /tmp/artifacts tar pipeline failed with exit code 2 using /usr/bin/ssh | /usr/bin/tar: tar stdout failure"))
        }
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
            XCTAssertEqual(error as? DownloadError, .remoteInspectionFailed("target devbox remote path ~/runs/second.png inspection failed with exit code 2: missing"))
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
