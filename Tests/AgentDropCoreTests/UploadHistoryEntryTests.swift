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
