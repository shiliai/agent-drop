import XCTest
@testable import AgentDropCore

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
