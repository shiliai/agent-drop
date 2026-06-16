import XCTest
@testable import AgentDropCore

final class UploadFeedbackFormatterTests: XCTestCase {
    func testSuccessMessageMentionsUploadAndCopiedPath() {
        let message = UploadFeedbackFormatter.success(fileCount: 1, targetName: "x570", copiedPaths: true)

        XCTAssertEqual(message, "Uploaded 1 file to x570. Path copied.")
    }

    func testSuccessMessageMentionsClipboardFailure() {
        let message = UploadFeedbackFormatter.success(fileCount: 2, targetName: "x570", copiedPaths: false)

        XCTAssertEqual(message, "Uploaded 2 files to x570, but could not copy paths.")
    }

    func testFailureMessageKeepsErrorShort() {
        let message = UploadFeedbackFormatter.failure(
            targetName: "x570",
            errorDescription: "Error Domain=NSCocoaErrorDomain Code=513 \"agent-drop-ui-test.png could not be copied\" UserInfo={very long internal details}"
        )

        XCTAssertEqual(message, "Upload to x570 failed. agent-drop-ui-test.png could not be copied")
    }

    func testFailureReasonExtractsUploadErrorAssociatedMessage() {
        XCTAssertEqual(
            UploadFeedbackFormatter.shortReason(from: String(describing: UploadError.rsyncFailed("Permission denied"))),
            "Permission denied"
        )
    }
}
