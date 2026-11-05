import XCTest
@testable import AgentDropCore

final class DownloadServiceTests: XCTestCase {
    func testDefaultDestinationRootUsesAgentDropDownloadsFolder() {
        XCTAssertEqual(DownloadService.defaultDestinationRoot(homeDirectory: URL(fileURLWithPath: "/Users/alex")).path, "/Users/alex/Downloads/Agent Drop")
    }

    func testPrepareDefaultDestinationRootCreatesFolder() throws {
        let transport = try TransferTestTransport()
        let root = try DownloadService.prepareDefaultDestinationRoot(homeDirectory: transport.root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    }

    func testFailsWhenRemotePathListIsEmpty() throws {
        let transport = try TransferTestTransport()
        XCTAssertThrowsError(try transport.download().download(remotePaths: [], target: transport.target, destinationRoot: transport.downloads)) {
            XCTAssertEqual($0 as? DownloadError, .noRemotePaths)
        }
        XCTAssertTrue(transport.invocations.isEmpty)
    }

    func testDownloadsRegularFileAndCopiesFinalLocalPath() throws {
        let transport = try TransferTestTransport()
        _ = try transport.file("home/runs/output.png", text: "image")
        let result = try XCTUnwrap(transport.pull("~/runs/output.png").first)
        XCTAssertEqual(result.localURL, transport.downloads.appendingPathComponent("output.png"))
        XCTAssertEqual(result.strategy, .rsyncFile)
        XCTAssertEqual(transport.clipboard.text, result.localDisplayPath)
    }

    func testMatchingHostHintByNameOrConnectNameProceedsNormally() throws {
        let transport = try TransferTestTransport()
        _ = try transport.file("home/runs/output.png", text: "image")
        let target = SSHTarget(name: "Display Name", connectName: "isolated", source: .config)
        for hint in [target.name, target.connectName] {
            let result = try transport.download().download(remotePaths: [RemotePath(hostHint: hint, path: "~/runs/output.png")], target: target, destinationRoot: transport.downloads)
            XCTAssertEqual(result.count, 1)
        }
    }

    func testHostHintMismatchFailsBeforeInspectionOrTransfer() throws {
        let transport = try TransferTestTransport()
        XCTAssertThrowsError(try transport.download().download(remotePaths: [RemotePath(hostHint: "another", path: "~/runs/output.png")], target: transport.target, destinationRoot: transport.downloads)) {
            XCTAssertEqual($0 as? DownloadError, .hostHintMismatch(hostHint: "another", selectedTarget: "isolated"))
        }
        XCTAssertTrue(transport.invocations.isEmpty)
    }

    func testRejectsRelativePathBeforeInspection() throws {
        let transport = try TransferTestTransport()
        XCTAssertThrowsError(try transport.pull("relative/output.png")) {
            XCTAssertEqual($0 as? DownloadError, .unsupportedRemotePath("relative/output.png"))
        }
        XCTAssertTrue(transport.invocations.isEmpty)
    }

    func testMissingRemotePathIncludesTargetPathAndExitCode() throws {
        let transport = try TransferTestTransport()
        XCTAssertThrowsError(try transport.pull("~/missing")) { error in
            guard case let DownloadError.remoteInspectionFailed(message) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("target isolated remote path ~/missing"))
            XCTAssertTrue(message.contains("exit code 2"))
        }
    }

    func testMalformedInspectionFailsClosed() throws {
        let transport = try TransferTestTransport()
        for output in ["", "file", "directory\n-1\n", "directory\nabc\n", "garbage\n"] {
            transport.sshOverride = { _ in .success(stdout: output, stderr: "") }
            XCTAssertThrowsError(try transport.pull("~/runs/output.png"))
        }
        XCTAssertEqual(transport.rsyncCount, 0)
    }

    func testFailedRsyncDoesNotPublishOutputOrClipboard() throws {
        let transport = try TransferTestTransport()
        _ = try transport.file("home/runs/output.png", text: "image")
        transport.rsyncFailure = .failure(exitCode: 23, stdout: "", stderr: "rsync failed")
        XCTAssertThrowsError(try transport.pull("~/runs/output.png")) { error in
            guard case let DownloadError.rsyncFailed(message) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("exit code 23"))
            XCTAssertTrue(message.contains("rsync failed"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: transport.downloads.appendingPathComponent("output.png").path))
        XCTAssertNil(transport.clipboard.text)
    }

    func testClipboardFailurePreservesOutputForNextSkip() throws {
        let transport = try TransferTestTransport()
        _ = try transport.file("home/runs/output.png", text: "image")
        transport.clipboard.fail = true
        XCTAssertThrowsError(try transport.pull("~/runs/output.png")) {
            XCTAssertEqual($0 as? DownloadError, .clipboardFailed("pasteboard unavailable"))
        }
        transport.clipboard.fail = false
        XCTAssertEqual(try transport.pull("~/runs/output.png").first?.wasSkipped, true)
        XCTAssertEqual(transport.rsyncCount, 1)
    }

    func testCanDownloadWithoutWritingClipboard() throws {
        let transport = try TransferTestTransport()
        _ = try transport.file("home/runs/output.png", text: "image")
        _ = try transport.download().download(remotePaths: [RemotePath(hostHint: nil, path: "~/runs/output.png")], target: transport.target,
                                             destinationRoot: transport.downloads, copyToClipboard: false)
        XCTAssertNil(transport.clipboard.text)
    }

    func testAllOrNothingClipboardWhenLaterPathFails() throws {
        let transport = try TransferTestTransport()
        _ = try transport.file("home/runs/first.png", text: "image")
        XCTAssertThrowsError(try transport.download().download(remotePaths: [RemotePath(hostHint: nil, path: "~/runs/first.png"), RemotePath(hostHint: nil, path: "~/missing")], target: transport.target, destinationRoot: transport.downloads))
        XCTAssertTrue(FileManager.default.fileExists(atPath: transport.downloads.appendingPathComponent("first.png").path))
        XCTAssertNil(transport.clipboard.text)
    }
}
