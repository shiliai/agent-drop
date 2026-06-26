import XCTest
@testable import AgentDropCore

final class UploadHistoryFileWatcherTests: XCTestCase {
    func testNotifiesWhenHistoryFileChangesAfterStart() throws {
        let root = try temporaryDirectory()
        let historyURL = root.appendingPathComponent("upload-history.json")
        let expectation = expectation(description: "history changed")
        expectation.assertForOverFulfill = false
        let watcher = UploadHistoryFileWatcher(historyFileURL: historyURL) {
            expectation.fulfill()
        }

        XCTAssertTrue(watcher.start())
        try Data("[]".utf8).write(to: historyURL)

        wait(for: [expectation], timeout: 2)
        watcher.stop()
    }

    func testNotifiesAfterStopAndRestart() throws {
        let root = try temporaryDirectory()
        let historyURL = root.appendingPathComponent("upload-history.json")
        let expectation = expectation(description: "history changed after restart")
        expectation.assertForOverFulfill = false
        let watcher = UploadHistoryFileWatcher(historyFileURL: historyURL) {
            expectation.fulfill()
        }

        XCTAssertTrue(watcher.start())
        watcher.stop()
        XCTAssertTrue(watcher.start())
        try Data("[]".utf8).write(to: historyURL)

        wait(for: [expectation], timeout: 2)
        watcher.stop()
    }

    func testNotifiesWhenHistoryStoreAppendsEntryAtomically() throws {
        let root = try temporaryDirectory()
        let historyURL = root.appendingPathComponent("upload-history.json")
        let store = UploadHistoryStore(historyFileURL: historyURL)
        let expectation = expectation(description: "history store append changed file")
        expectation.assertForOverFulfill = false
        let watcher = UploadHistoryFileWatcher(historyFileURL: historyURL) {
            expectation.fulfill()
        }

        XCTAssertTrue(watcher.start())
        try store.append(
            UploadHistoryEntry(
                id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                createdAt: Date(timeIntervalSince1970: 1_803_427_200),
                targetName: "x570",
                status: .succeeded,
                localFileNames: ["report.pdf"],
                remoteDisplayPaths: ["~/.agent-inbox/2026-06-26/report.pdf"],
                errorMessage: nil
            )
        )

        wait(for: [expectation], timeout: 2)
        watcher.stop()
    }
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
