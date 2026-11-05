import XCTest
@testable import AgentDropCore

final class UploadServiceTests: XCTestCase {
    func testUploadsFileAndCopiesFinalRemotePath() throws {
        let transport = try TransferTestTransport()
        let source = try transport.file("source/demo.png", text: "image")
        let result = try transport.upload().upload(files: [source], target: transport.target)
        XCTAssertEqual(result.map(\.remoteDisplayPath), ["~/.agent-inbox/2026-06-15/demo.png"])
        XCTAssertEqual(transport.clipboard.text, result.first?.remoteDisplayPath)
        XCTAssertEqual(try Data(contentsOf: transport.uploadedURL(try XCTUnwrap(result.first))), Data("image".utf8))
    }

    func testUploadsStagedSourcePreservingOriginalNameAndDisplayName() throws {
        let transport = try TransferTestTransport()
        let source = try transport.file("staging/0-image.png", text: "image")
        let result = try transport.upload().upload(sources: [UploadSourceFile(sourceURL: source, remoteName: "demo.png", localDisplayName: "Screenshot")], target: transport.target)
        XCTAssertEqual(result.first?.remoteDisplayPath, "~/.agent-inbox/2026-06-15/demo.png")
        XCTAssertEqual(result.first?.localDisplayName, "Screenshot")
        XCTAssertEqual(result.first?.localURL, source)
    }

    func testCanUploadWithoutWritingClipboard() throws {
        let transport = try TransferTestTransport()
        let source = try transport.file("source/demo.png", text: "image")
        _ = try transport.upload().upload(files: [source], target: transport.target, copyToClipboard: false)
        XCTAssertNil(transport.clipboard.text)
    }

    func testClipboardFailurePreservesVerifiedUploadForNextSkip() throws {
        let transport = try TransferTestTransport()
        let source = try transport.file("source/demo.png", text: "image")
        transport.clipboard.fail = true
        XCTAssertThrowsError(try transport.upload().upload(files: [source], target: transport.target)) {
            XCTAssertEqual($0 as? UploadError, .clipboardFailed("pasteboard unavailable"))
        }
        transport.clipboard.fail = false
        XCTAssertEqual(try transport.upload().upload(files: [source], target: transport.target).first?.wasSkipped, true)
        XCTAssertEqual(transport.rsyncCount, 1)
    }

    func testRemoteDirectoryFailureStopsBeforeTransfer() throws {
        let transport = try TransferTestTransport()
        transport.sshOverride = { _ in .failure(exitCode: 255, stdout: "", stderr: "ssh failed") }
        XCTAssertThrowsError(try transport.upload().upload(files: [URL(fileURLWithPath: "/missing")], target: transport.target)) {
            XCTAssertEqual($0 as? UploadError, .remoteDirectoryFailed("ssh failed"))
        }
        XCTAssertEqual(transport.rsyncCount, 0)
    }

    func testFailedRsyncDoesNotPublishOrWriteClipboard() throws {
        let transport = try TransferTestTransport()
        let source = try transport.file("source/demo.png", text: "image")
        transport.rsyncFailure = .failure(exitCode: 23, stdout: "", stderr: "rsync failed")
        XCTAssertThrowsError(try transport.upload().upload(files: [source], target: transport.target)) {
            XCTAssertEqual($0 as? UploadError, .rsyncFailed("rsync failed"))
        }
        XCTAssertNil(transport.clipboard.text)
        XCTAssertFalse(FileManager.default.fileExists(atPath: transport.home.appendingPathComponent(".agent-inbox/2026-06-15/demo.png").path))
    }

    func testExistenceInspectionFailureDoesNotFallBackToUploading() throws {
        let transport = try TransferTestTransport()
        let source = try transport.file("source/demo.png", text: "image")
        transport.sshOverride = { $0.hasPrefix("for d in") ? .failure(exitCode: 255, stdout: "", stderr: "inspection failed") : nil }
        XCTAssertThrowsError(try transport.upload().upload(files: [source], target: transport.target)) {
            XCTAssertEqual($0 as? UploadError, .remoteExistenceCheckFailed("inspection failed"))
        }
        XCTAssertEqual(transport.rsyncCount, 0)
    }

    func testCancelledRequestDoesNotStartRemoteCommands() throws {
        let transport = try TransferTestTransport()
        let cancellation = TransferCancellation()
        cancellation.cancel()
        XCTAssertThrowsError(try transport.upload().upload(files: [URL(fileURLWithPath: "/missing")], target: transport.target, cancellation: cancellation))
        XCTAssertTrue(transport.invocations.isEmpty)
    }

    func testRejectsRemoteNamesThatEscapeInbox() throws {
        let transport = try TransferTestTransport()
        let source = try transport.file("source/demo.png", text: "image")
        for name in ["../escape", ".", "..", ""] {
            XCTAssertThrowsError(try transport.upload().upload(sources: [UploadSourceFile(sourceURL: source, remoteName: name)], target: transport.target))
        }
        XCTAssertEqual(transport.rsyncCount, 0)
    }
}
