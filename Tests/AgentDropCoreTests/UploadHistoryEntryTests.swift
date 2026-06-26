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

    func testEncodesAndDecodesSucceededDownloadEntry() throws {
        let entry = UploadHistoryEntry.downloadSucceeded(
            targetName: "x570",
            downloadedFiles: [
                DownloadedFile(
                    remotePath: "~/reports/demo.png",
                    localURL: URL(fileURLWithPath: "/Users/chris/Downloads/Agent Drop/demo.png"),
                    localDisplayPath: "/Users/chris/Downloads/Agent Drop/demo.png",
                    strategy: .rsyncFile
                ),
                DownloadedFile(
                    remotePath: "/var/log/build.log",
                    localURL: URL(fileURLWithPath: "/Users/chris/Downloads/Agent Drop/build.log"),
                    localDisplayPath: "/Users/chris/Downloads/Agent Drop/build.log",
                    strategy: .rsyncFile
                )
            ],
            createdAt: Date(timeIntervalSince1970: 1_781_510_400),
            id: UUID(uuidString: "12121212-1212-1212-1212-121212121212")!
        )

        let data = try JSONEncoder.agentDropHistory.encode(entry)
        let decoded = try JSONDecoder.agentDropHistory.decode(UploadHistoryEntry.self, from: data)

        XCTAssertEqual(decoded.direction, .download)
        XCTAssertEqual(decoded.status, .succeeded)
        XCTAssertEqual(decoded.remoteDisplayPaths, ["~/reports/demo.png", "/var/log/build.log"])
        XCTAssertEqual(decoded.localDisplayPaths, [
            "/Users/chris/Downloads/Agent Drop/demo.png",
            "/Users/chris/Downloads/Agent Drop/build.log"
        ])
        XCTAssertEqual(decoded.localFileNames, ["demo.png", "build.log"])
        XCTAssertEqual(decoded, entry)
    }

    func testDecodesLegacyUploadJSONWithoutDirectionOrLocalDisplayPaths() throws {
        let json = """
        {
          "id": "13131313-1313-1313-1313-131313131313",
          "createdAt": "2026-06-15T00:00:00Z",
          "targetName": "x570",
          "status": "succeeded",
          "localFileNames": ["demo.png"],
          "remoteDisplayPaths": ["~/.agent-inbox/2026-06-15/demo.png"],
          "errorMessage": null
        }
        """

        let decoded = try JSONDecoder.agentDropHistory.decode(
            UploadHistoryEntry.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(decoded.direction, .upload)
        XCTAssertEqual(decoded.localDisplayPaths, [])
        XCTAssertEqual(decoded.localFileNames, ["demo.png"])
        XCTAssertEqual(decoded.remoteDisplayPaths, ["~/.agent-inbox/2026-06-15/demo.png"])
        XCTAssertEqual(decoded.copyPayload, "~/.agent-inbox/2026-06-15/demo.png")
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

    func testDownloadCopyPayloadJoinsLocalPathsWithNewlines() {
        let entry = UploadHistoryEntry.downloadSucceeded(
            targetName: "x570",
            downloadedFiles: [
                DownloadedFile(
                    remotePath: "~/reports/demo.png",
                    localURL: URL(fileURLWithPath: "/Users/chris/Downloads/Agent Drop/demo.png"),
                    localDisplayPath: "/Users/chris/Downloads/Agent Drop/demo.png",
                    strategy: .rsyncFile
                ),
                DownloadedFile(
                    remotePath: "/var/log/build.log",
                    localURL: URL(fileURLWithPath: "/Users/chris/Downloads/Agent Drop/build.log"),
                    localDisplayPath: "/Users/chris/Downloads/Agent Drop/build.log",
                    strategy: .rsyncFile
                )
            ]
        )

        XCTAssertEqual(
            entry.copyPayload,
            "/Users/chris/Downloads/Agent Drop/demo.png\n/Users/chris/Downloads/Agent Drop/build.log"
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

    func testFailedDownloadEntryHasNoCopyPayloadAndNormalizesDownloadError() {
        let entry = UploadHistoryEntry.downloadFailed(
            targetName: "x570",
            remotePaths: ["~/reports/demo.png"],
            errorDescription: String(describing: DownloadError.rsyncFailed("Permission denied")),
            createdAt: Date(timeIntervalSince1970: 123),
            id: UUID(uuidString: "34343434-3434-3434-3434-343434343434")!
        )

        XCTAssertEqual(entry.direction, .download)
        XCTAssertEqual(entry.status, .failed)
        XCTAssertEqual(entry.remoteDisplayPaths, ["~/reports/demo.png"])
        XCTAssertEqual(entry.localDisplayPaths, [])
        XCTAssertEqual(entry.localFileNames, [])
        XCTAssertEqual(entry.errorMessage, "Permission denied")
        XCTAssertNil(entry.copyPayload)
    }

    func testFailedDownloadEntryPreservesQuotedPathInsideDownloadErrorPayload() {
        let entry = UploadHistoryEntry.downloadFailed(
            targetName: "x570",
            remotePaths: ["~/reports/demo file.txt"],
            errorDescription: String(describing: DownloadError.rsyncFailed(
                #"rsync: link_stat "/tmp/demo file.txt" failed: No such file or directory (2)"#
            )),
            createdAt: Date(timeIntervalSince1970: 123),
            id: UUID(uuidString: "35353535-3535-3535-3535-353535353535")!
        )

        XCTAssertEqual(
            entry.errorMessage,
            #"rsync: link_stat "/tmp/demo file.txt" failed: No such file or directory (2)"#
        )
    }

    func testFailedDownloadEntryNormalizesDownloadSpecificErrorPayloads() {
        let entry = UploadHistoryEntry.downloadFailed(
            targetName: "x570",
            remotePaths: ["~/reports/demo.png"],
            errorDescription: String(describing: DownloadError.remoteInspectionFailed(
                #"inspection produced "unexpected" output"#
            )),
            createdAt: Date(timeIntervalSince1970: 123),
            id: UUID(uuidString: "36363636-3636-3636-3636-363636363636")!
        )

        XCTAssertEqual(entry.errorMessage, #"inspection produced "unexpected" output"#)
    }

    func testFailedDownloadEntryDoesNotCollapseLabeledDownloadErrorToFirstQuotedValue() {
        let entry = UploadHistoryEntry.downloadFailed(
            targetName: "x570",
            remotePaths: ["devbox:~/reports/demo.png"],
            errorDescription: String(describing: DownloadError.hostHintMismatch(
                hostHint: "devbox",
                selectedTarget: "x570"
            )),
            createdAt: Date(timeIntervalSince1970: 123),
            id: UUID(uuidString: "37373737-3737-3737-3737-373737373737")!
        )

        XCTAssertEqual(
            entry.errorMessage,
            #"hostHintMismatch(hostHint: "devbox", selectedTarget: "x570")"#
        )
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

    func testBuildsDownloadSucceededEntryFromDownloadedFiles() {
        let downloaded = [
            DownloadedFile(
                remotePath: "~/reports/demo.png",
                localURL: URL(fileURLWithPath: "/Users/chris/Downloads/Agent Drop/demo.png"),
                localDisplayPath: "/Users/chris/Downloads/Agent Drop/demo.png",
                strategy: .rsyncFile
            )
        ]

        let entry = UploadHistoryEntry.downloadSucceeded(
            targetName: "x570",
            downloadedFiles: downloaded,
            createdAt: Date(timeIntervalSince1970: 123),
            id: UUID(uuidString: "46464646-4646-4646-4646-464646464646")!
        )

        XCTAssertEqual(entry.direction, .download)
        XCTAssertEqual(entry.status, .succeeded)
        XCTAssertEqual(entry.targetName, "x570")
        XCTAssertEqual(entry.remoteDisplayPaths, ["~/reports/demo.png"])
        XCTAssertEqual(entry.localDisplayPaths, ["/Users/chris/Downloads/Agent Drop/demo.png"])
        XCTAssertEqual(entry.localFileNames, ["demo.png"])
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
