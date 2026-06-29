import XCTest
@testable import AgentDropCore

private func fixedUUID(_ value: UInt8) -> UUID {
    UUID(uuid: (
        value, value, value, value,
        value, value, value, value,
        value, value, value, value,
        value, value, value, value
    ))
}

final class TransferStatusSummaryTests: XCTestCase {
    func testProgressMessageTakesPriorityOverHistoryTimestamp() {
        let summary = TransferStatusSummary.progress("Uploading clipboard contents...")

        XCTAssertEqual(summary.statusText(lastUpdatedAt: Date(timeIntervalSince1970: 0)), "Uploading clipboard contents...")
        XCTAssertEqual(summary.systemImageName, "arrow.up.circle.fill")
    }

    func testUploadSuccessMentionsCopiedPaths() {
        let summary = TransferStatusSummary.uploadSuccess(fileCount: 2, targetName: "devbox", copiedPaths: true)

        XCTAssertEqual(summary.statusText(lastUpdatedAt: nil), "Uploaded 2 files to devbox. Path copied.")
        XCTAssertEqual(summary.systemImageName, "checkmark.circle.fill")
    }

    func testUploadSuccessMentionsClipboardCopyFailure() {
        let summary = TransferStatusSummary.uploadSuccess(fileCount: 1, targetName: "devbox", copiedPaths: false)

        XCTAssertEqual(summary.statusText(lastUpdatedAt: nil), "Uploaded 1 file to devbox, but could not copy paths.")
        XCTAssertEqual(summary.systemImageName, "exclamationmark.triangle.fill")
    }

    func testRunningFinderUploadHistoryProducesProgressSummary() {
        let entry = UploadHistoryEntry.uploadStarted(
            targetName: "x570",
            fileURLs: [
                URL(fileURLWithPath: "/tmp/design.pdf"),
                URL(fileURLWithPath: "/tmp/screenshots")
            ],
            createdAt: Date(timeIntervalSince1970: 1_000)
        )

        let summary = TransferStatusSummary.runningUploadHistoryStatus(
            from: [entry],
            now: Date(timeIntervalSince1970: 1_060),
            staleAfter: 1_800
        )

        XCTAssertEqual(summary, .progress("Uploading 2 files to x570..."))
    }

    func testNewestNonStaleRunningFinderUploadWins() {
        let older = UploadHistoryEntry.uploadStarted(
            targetName: "old",
            fileURLs: [URL(fileURLWithPath: "/tmp/old.png")],
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let newer = UploadHistoryEntry.uploadStarted(
            targetName: "new",
            fileURLs: [URL(fileURLWithPath: "/tmp/new.png")],
            createdAt: Date(timeIntervalSince1970: 1_100)
        )

        let summary = TransferStatusSummary.runningUploadHistoryStatus(
            from: [older, newer],
            now: Date(timeIntervalSince1970: 1_120),
            staleAfter: 1_800
        )

        XCTAssertEqual(summary, .progress("Uploading 1 file to new..."))
    }

    func testStaleRunningFinderUploadDoesNotDriveProgressSummary() {
        let entry = UploadHistoryEntry.uploadStarted(
            targetName: "x570",
            fileURLs: [URL(fileURLWithPath: "/tmp/design.pdf")],
            createdAt: Date(timeIntervalSince1970: 1_000)
        )

        let summary = TransferStatusSummary.runningUploadHistoryStatus(
            from: [entry],
            now: Date(timeIntervalSince1970: 3_001),
            staleAfter: 1_800
        )

        XCTAssertNil(summary)
    }

    func testCompletedHistoryDoesNotDriveProgressSummary() {
        let entry = UploadHistoryEntry.succeeded(
            targetName: "x570",
            uploadedFiles: [
                UploadedFile(
                    localURL: URL(fileURLWithPath: "/tmp/design.pdf"),
                    remoteDisplayPath: "~/.agent-inbox/2026-06-29/design.pdf"
                )
            ],
            createdAt: Date(timeIntervalSince1970: 1_000)
        )

        let summary = TransferStatusSummary.runningUploadHistoryStatus(
            from: [entry],
            now: Date(timeIntervalSince1970: 1_010),
            staleAfter: 1_800
        )

        XCTAssertNil(summary)
    }

    func testNewFinderUploadCanReplacePriorTerminalStatus() {
        XCTAssertTrue(TransferStatusSummary.canShowRunningFinderUpload(
            currentStatus: .success("Uploaded 1 file to x570."),
            isShowingFinderUploadStatus: false
        ))
        XCTAssertTrue(TransferStatusSummary.canShowRunningFinderUpload(
            currentStatus: .failure("Upload to x570 failed."),
            isShowingFinderUploadStatus: false
        ))
        XCTAssertTrue(TransferStatusSummary.canShowRunningFinderUpload(
            currentStatus: .uploadSuccess(fileCount: 1, targetName: "x570", copiedPaths: true),
            isShowingFinderUploadStatus: false
        ))
    }

    func testFinderUploadDoesNotReplaceNonFinderProgress() {
        XCTAssertFalse(TransferStatusSummary.canShowRunningFinderUpload(
            currentStatus: .progress("Downloading 1 file from x570..."),
            isShowingFinderUploadStatus: false
        ))
    }

    func testFinderUploadCanRefreshItsOwnProgress() {
        XCTAssertTrue(TransferStatusSummary.canShowRunningFinderUpload(
            currentStatus: .progress("Uploading 1 file to x570..."),
            isShowingFinderUploadStatus: true
        ))
    }

    func testFinderUploadStatusSyncShowsNewRunningAfterPriorFinderSuccess() {
        let running = UploadHistoryEntry.uploadStarted(
            id: fixedUUID(0x41),
            targetName: "a100",
            fileURLs: [URL(fileURLWithPath: "/tmp/next.png")],
            createdAt: Date(timeIntervalSince1970: 2_000)
        )

        let resolution = FinderUploadStatusResolver.resolve(
            entries: [running],
            currentStatus: .success("Uploaded 1 file to x570."),
            activeUploadID: nil,
            isShowingFinderUploadStatus: false,
            now: Date(timeIntervalSince1970: 2_005),
            staleAfter: 1_800
        )

        XCTAssertEqual(resolution.transferStatusSummary, .progress("Uploading 1 file to a100..."))
        XCTAssertEqual(resolution.activeUploadID, running.id)
        XCTAssertTrue(resolution.isShowingFinderUploadStatus)
        XCTAssertEqual(resolution.staleRefreshEntry, running)
    }

    func testFinderUploadStatusSyncPreservesNonFinderProgress() {
        let running = UploadHistoryEntry.uploadStarted(
            id: fixedUUID(0x42),
            targetName: "a100",
            fileURLs: [URL(fileURLWithPath: "/tmp/next.png")],
            createdAt: Date(timeIntervalSince1970: 2_000)
        )

        let resolution = FinderUploadStatusResolver.resolve(
            entries: [running],
            currentStatus: .progress("Downloading 1 file from x570..."),
            activeUploadID: nil,
            isShowingFinderUploadStatus: false,
            now: Date(timeIntervalSince1970: 2_005),
            staleAfter: 1_800
        )

        XCTAssertEqual(resolution.transferStatusSummary, .progress("Downloading 1 file from x570..."))
        XCTAssertNil(resolution.activeUploadID)
        XCTAssertFalse(resolution.isShowingFinderUploadStatus)
        XCTAssertNil(resolution.staleRefreshEntry)
    }

    func testFinderUploadStatusSyncCanCompleteThenShowNextRunningUpload() {
        let firstID = fixedUUID(0x43)
        let firstStarted = UploadHistoryEntry.uploadStarted(
            id: firstID,
            targetName: "x570",
            fileURLs: [URL(fileURLWithPath: "/tmp/first.png")],
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        let firstCompleted = UploadHistoryEntry.succeeded(
            targetName: "x570",
            uploadedFiles: [
                UploadedFile(
                    localURL: URL(fileURLWithPath: "/tmp/first.png"),
                    remoteDisplayPath: "~/.agent-inbox/2026-06-29/first.png"
                )
            ],
            createdAt: Date(timeIntervalSince1970: 2_000),
            id: firstID
        )
        let secondStarted = UploadHistoryEntry.uploadStarted(
            id: fixedUUID(0x44),
            targetName: "a100",
            fileURLs: [URL(fileURLWithPath: "/tmp/second.png")],
            createdAt: Date(timeIntervalSince1970: 2_100)
        )

        let runningResolution = FinderUploadStatusResolver.resolve(
            entries: [firstStarted],
            currentStatus: .idle,
            activeUploadID: nil,
            isShowingFinderUploadStatus: false,
            now: Date(timeIntervalSince1970: 2_005),
            staleAfter: 1_800
        )
        let completedResolution = FinderUploadStatusResolver.resolve(
            entries: [firstCompleted],
            currentStatus: runningResolution.transferStatusSummary,
            activeUploadID: runningResolution.activeUploadID,
            isShowingFinderUploadStatus: runningResolution.isShowingFinderUploadStatus,
            now: Date(timeIntervalSince1970: 2_020),
            staleAfter: 1_800
        )
        let nextRunningResolution = FinderUploadStatusResolver.resolve(
            entries: [secondStarted, firstCompleted],
            currentStatus: completedResolution.transferStatusSummary,
            activeUploadID: completedResolution.activeUploadID,
            isShowingFinderUploadStatus: completedResolution.isShowingFinderUploadStatus,
            now: Date(timeIntervalSince1970: 2_105),
            staleAfter: 1_800
        )

        XCTAssertEqual(completedResolution.transferStatusSummary, .success("Uploaded 1 file to x570."))
        XCTAssertNil(completedResolution.activeUploadID)
        XCTAssertFalse(completedResolution.isShowingFinderUploadStatus)
        XCTAssertEqual(nextRunningResolution.transferStatusSummary, .progress("Uploading 1 file to a100..."))
        XCTAssertEqual(nextRunningResolution.activeUploadID, secondStarted.id)
        XCTAssertTrue(nextRunningResolution.isShowingFinderUploadStatus)
    }

    func testGenericSuccessMessageIsUserVisible() {
        let summary = TransferStatusSummary.success("Uploaded 2 files to x570.")

        XCTAssertEqual(summary.statusText(lastUpdatedAt: nil), "Uploaded 2 files to x570.")
        XCTAssertEqual(summary.systemImageName, "checkmark.circle.fill")
    }

    func testFailureMessageIsUserVisible() {
        let summary = TransferStatusSummary.failure("Could not upload screenshot.")

        XCTAssertEqual(summary.statusText(lastUpdatedAt: nil), "Could not upload screenshot.")
        XCTAssertEqual(summary.systemImageName, "xmark.circle.fill")
    }

    func testIdleFallsBackToHistoryTimestamp() {
        let summary = TransferStatusSummary.idle

        XCTAssertEqual(summary.statusText(lastUpdatedAt: nil), "Last updated: never")
        let timestamp = summary.statusText(
            lastUpdatedAt: Date(timeIntervalSince1970: 3_600),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        XCTAssertTrue(timestamp.hasPrefix("Last updated: 1:00:00"))
        XCTAssertEqual(summary.systemImageName, "circle.fill")
    }
}
