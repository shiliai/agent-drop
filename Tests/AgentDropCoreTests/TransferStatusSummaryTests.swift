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
