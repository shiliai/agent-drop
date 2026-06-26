import XCTest
@testable import AgentDropCore

final class UploadHistoryEntryTests: XCTestCase {
    func testEncodesAndDecodesSucceededEntry() throws {
        let entry = UploadHistoryEntry(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            createdAt: Date(timeIntervalSince1970: 1_781_510_400),
            targetName: "x570",
            status: .succeeded,
            localFileNames: ["demo.png", "spec.pdf"],
            remoteDisplayPaths: [
                "~/.agent-inbox/2026-06-15/demo.png",
                "~/.agent-inbox/2026-06-15/spec.pdf"
            ],
            errorMessage: nil
        )

        let data = try JSONEncoder.agentDropHistory.encode(entry)
        let decoded = try JSONDecoder.agentDropHistory.decode(UploadHistoryEntry.self, from: data)

        XCTAssertEqual(decoded, entry)
    }

    func testCopyPayloadJoinsRemotePathsWithNewlines() {
        let entry = UploadHistoryEntry(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            createdAt: Date(timeIntervalSince1970: 1_781_510_400),
            targetName: "x570",
            status: .succeeded,
            localFileNames: ["demo.png", "spec.pdf"],
            remoteDisplayPaths: [
                "~/.agent-inbox/2026-06-15/demo.png",
                "~/.agent-inbox/2026-06-15/spec.pdf"
            ],
            errorMessage: nil
        )

        XCTAssertEqual(
            entry.copyPayload,
            "~/.agent-inbox/2026-06-15/demo.png\n~/.agent-inbox/2026-06-15/spec.pdf"
        )
    }

    func testFailedEntryHasNoCopyPayload() {
        let entry = UploadHistoryEntry(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            createdAt: Date(timeIntervalSince1970: 1_781_510_400),
            targetName: "x570",
            status: .failed,
            localFileNames: ["demo.png"],
            remoteDisplayPaths: [],
            errorMessage: "Upload to x570 failed. rsync failed"
        )

        XCTAssertNil(entry.copyPayload)
    }

    func testBuildsSucceededEntryFromUploadedFiles() {
        let uploaded = [
            UploadedFile(
                localURL: URL(fileURLWithPath: "/tmp/demo.png"),
                remoteDisplayPath: "~/.agent-inbox/2026-06-15/demo.png"
            )
        ]

        let entry = UploadHistoryEntry.succeeded(
            targetName: "x570",
            uploadedFiles: uploaded,
            createdAt: Date(timeIntervalSince1970: 123),
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        )

        XCTAssertEqual(entry.status, .succeeded)
        XCTAssertEqual(entry.targetName, "x570")
        XCTAssertEqual(entry.localFileNames, ["demo.png"])
        XCTAssertEqual(entry.remoteDisplayPaths, ["~/.agent-inbox/2026-06-15/demo.png"])
        XCTAssertNil(entry.errorMessage)
    }

    func testBuildsSucceededEntryUsingOriginalDisplayNamesInsteadOfStagedLocalNames() {
        let uploaded = [
            UploadedFile(
                localURL: URL(fileURLWithPath: "/tmp/AgentDropUploads/fixed/0-demo.png"),
                remoteDisplayPath: "~/.agent-inbox/2026-06-15/demo.png",
                localDisplayName: "demo.png"
            )
        ]

        let entry = UploadHistoryEntry.succeeded(
            targetName: "x570",
            uploadedFiles: uploaded,
            createdAt: Date(timeIntervalSince1970: 123),
            id: UUID(uuidString: "45454545-4545-4545-4545-454545454545")!
        )

        XCTAssertEqual(entry.localFileNames, ["demo.png"])
    }

    func testBuildsFailedEntryFromSelectedFiles() {
        let entry = UploadHistoryEntry.failed(
            targetName: "x570",
            fileURLs: [URL(fileURLWithPath: "/tmp/demo.png")],
            errorDescription: String(repeating: "x", count: 180),
            createdAt: Date(timeIntervalSince1970: 123),
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        )

        XCTAssertEqual(entry.status, .failed)
        XCTAssertEqual(entry.targetName, "x570")
        XCTAssertEqual(entry.localFileNames, ["demo.png"])
        XCTAssertEqual(entry.remoteDisplayPaths, [])
        XCTAssertEqual(entry.errorMessage, String(repeating: "x", count: 117) + "...")
    }

    func testBuildsFailedEntryUsingNormalizedUserFacingReason() {
        let entry = UploadHistoryEntry.failed(
            targetName: "x570",
            fileURLs: [URL(fileURLWithPath: "/tmp/demo.png")],
            errorDescription: String(describing: UploadError.rsyncFailed("Permission denied")),
            createdAt: Date(timeIntervalSince1970: 123),
            id: UUID(uuidString: "56565656-5656-5656-5656-565656565656")!
        )

        XCTAssertEqual(entry.errorMessage, "Permission denied")
    }

    func testBuildsFailedEntryPreservingQuotedPathInsideUploadErrorPayload() {
        let errorDescription = #"rsyncFailed("rsync: [sender] link_stat \"/tmp/demo file.txt\" failed: No such file or directory (2)")"#
        let entry = UploadHistoryEntry.failed(
            targetName: "x570",
            fileURLs: [URL(fileURLWithPath: "/tmp/demo.png")],
            errorDescription: errorDescription,
            createdAt: Date(timeIntervalSince1970: 123),
            id: UUID(uuidString: "57575757-5757-5757-5757-575757575757")!
        )

        XCTAssertEqual(
            entry.errorMessage,
            #"rsync: [sender] link_stat "/tmp/demo file.txt" failed: No such file or directory (2)"#
        )
    }

    func testFailureMessageTrimsLeadingAndTrailingWhitespaceForHistoryDisplay() {
        XCTAssertEqual(
            UploadHistoryEntry.shortErrorMessage(from: "  rsync failed\n"),
            "rsync failed"
        )
    }

    func testFailureMessageIsTruncatedForHistoryDisplay() {
        let longMessage = String(repeating: "x", count: 180)

        XCTAssertEqual(
            UploadHistoryEntry.shortErrorMessage(from: longMessage),
            String(repeating: "x", count: 117) + "..."
        )
    }
}
