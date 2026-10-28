import XCTest
@testable import AgentDropCore

final class TransferActivityOrderingTests: XCTestCase {
    func testRecentSuccessIsNotHiddenBehindOlderFailures() {
        let failed = entry(.failed, createdAt: 10)
        let succeeded = entry(.succeeded, createdAt: 30)
        let newerFailure = entry(.failed, createdAt: 40)

        XCTAssertEqual(
            TransferActivityOrdering.ordered([failed, succeeded, newerFailure]).map(\.id),
            [newerFailure.id, succeeded.id, failed.id]
        )
    }

    func testActiveTransfersStayAboveNewerCompletedTransfers() {
        let active = entry(.running, createdAt: 10)
        let completed = entry(.succeeded, createdAt: 100)
        let newerActive = entry(.running, createdAt: 20)

        XCTAssertEqual(
            TransferActivityOrdering.ordered([completed, active, newerActive]).map(\.id),
            [newerActive.id, active.id, completed.id]
        )
    }

    func testCompletedTransfersUseFinishTimeWithLegacyCreationTimeFallback() {
        let longTransfer = entry(.succeeded, createdAt: 10, completedAt: 100)
        let legacy = entry(.failed, createdAt: 50)
        let shortTransfer = entry(.succeeded, createdAt: 60, completedAt: 70)

        XCTAssertEqual(
            TransferActivityOrdering.ordered([legacy, shortTransfer, longTransfer]).map(\.id),
            [longTransfer.id, shortTransfer.id, legacy.id]
        )
    }

    func testAllRecordsAndStatusesArePreserved() {
        let entries = (0..<100).map { index in
            entry(index < 18 ? .failed : .succeeded, createdAt: Double(index))
        }
        let ordered = TransferActivityOrdering.ordered(entries)

        XCTAssertEqual(ordered.count, 100)
        XCTAssertEqual(Set(ordered.map(\.id)), Set(entries.map(\.id)))
        XCTAssertEqual(ordered.filter { $0.status == .succeeded }.count, 82)
        XCTAssertEqual(ordered.filter { $0.status == .failed }.count, 18)
        XCTAssertEqual(ordered.first?.status, .succeeded)
    }

    func testEqualTimestampsUseStableOrder() throws {
        let first = UploadHistoryEntry(
            id: try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111")),
            createdAt: Date(timeIntervalSince1970: 10), targetName: "host", status: .succeeded,
            localFileNames: ["a"], remoteDisplayPaths: [], errorMessage: nil
        )
        let second = UploadHistoryEntry(
            id: try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            createdAt: first.createdAt, targetName: "host", status: .failed,
            localFileNames: ["b"], remoteDisplayPaths: [], errorMessage: "Failed"
        )

        XCTAssertEqual(TransferActivityOrdering.ordered([second, first]), [first, second])
        XCTAssertEqual(TransferActivityOrdering.ordered([first, second]), [first, second])
    }

    private func entry(_ status: UploadHistoryEntry.Status, createdAt: TimeInterval, completedAt: TimeInterval? = nil) -> UploadHistoryEntry {
        UploadHistoryEntry(
            createdAt: Date(timeIntervalSince1970: createdAt), targetName: "host", status: status,
            localFileNames: ["sample.dat"], remoteDisplayPaths: [], errorMessage: status == .failed ? "Failed" : nil,
            completedAt: completedAt.map { Date(timeIntervalSince1970: $0) }
        )
    }
}
