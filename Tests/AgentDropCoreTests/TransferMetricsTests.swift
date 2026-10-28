import XCTest
@testable import AgentDropCore

final class TransferMetricsTests: XCTestCase {
    func testSubsecondDurationSurvivesSecondPrecisionHistoryDates() throws {
        let entry = UploadHistoryEntry(
            targetName: "host", status: .succeeded, localFileNames: ["tiny.txt"], remoteDisplayPaths: [], errorMessage: nil
        ).withMetrics(
            startedAt: Date(timeIntervalSince1970: 100.1), completedAt: Date(timeIntervalSince1970: 100.2),
            totalBytes: 100, transferredBytes: 100
        )
        let decoded = try JSONDecoder.agentDropHistory.decode(UploadHistoryEntry.self, from: JSONEncoder.agentDropHistory.encode(entry))
        XCTAssertEqual(try XCTUnwrap(decoded.averageBytesPerSecond()), 1_000, accuracy: 0.01)
        XCTAssertGreaterThan(try XCTUnwrap(decoded.duration), 0)
    }

    func testMetricsRoundTripAndAverageExcludeQueueTime() throws {
        let entry = UploadHistoryEntry(
            createdAt: Date(timeIntervalSince1970: 10), targetName: "host", status: .succeeded,
            localFileNames: ["data.bin"], remoteDisplayPaths: ["~/data.bin"], errorMessage: nil,
            startedAt: Date(timeIntervalSince1970: 100), completedAt: Date(timeIntervalSince1970: 110),
            totalBytes: 1_000, transferredBytes: 1_000
        )
        XCTAssertEqual(entry.averageBytesPerSecond(now: Date(timeIntervalSince1970: 999)), 100)
        let decoded = try JSONDecoder.agentDropHistory.decode(UploadHistoryEntry.self, from: JSONEncoder.agentDropHistory.encode(entry))
        XCTAssertEqual(decoded, entry)
        XCTAssertEqual(decoded.updatingProgress(nil).totalBytes, 1_000)
    }

    func testLiveAverageForSingleFileUsesTransferredBytesNotFileSize() {
        let request = TransferRequest.upload(target: SSHTarget(name: "host", source: .config), sources: [
            UploadSourceFile(sourceURL: URL(fileURLWithPath: "/tmp/data.bin"), remoteName: "data.bin")
        ])
        let entry = request.entry(id: UUID(), createdAt: .distantPast, status: .running)
            .withMetrics(startedAt: Date(timeIntervalSince1970: 100), totalBytes: 1_000)
            .updatingProgress(TransferProgress(completedBytes: 250, fractionCompleted: 0.25, bytesPerSecond: 99, estimatedTimeRemaining: nil))
        XCTAssertEqual(entry.averageBytesPerSecond(now: Date(timeIntervalSince1970: 110)), 25)
    }

    func testDirectoryProgressCannotBeMistakenForWholeDirectoryAverage() {
        let request = TransferRequest.upload(target: SSHTarget(name: "host", source: .config), sources: [
            UploadSourceFile(sourceURL: URL(fileURLWithPath: "/tmp/folder"), remoteName: "folder", isDirectory: true)
        ])
        let entry = request.entry(id: UUID(), createdAt: .now, status: .running)
            .withMetrics(startedAt: Date(timeIntervalSince1970: 100), totalBytes: 1_000)
            .updatingProgress(TransferProgress(completedBytes: 250, fractionCompleted: 1, bytesPerSecond: 99, estimatedTimeRemaining: nil))
        XCTAssertNil(entry.averageBytesPerSecond(now: Date(timeIntervalSince1970: 110)))
    }

    func testMissingAndZeroDurationMetricsDoNotInventAverage() {
        let entry = UploadHistoryEntry.failed(targetName: "host", fileURLs: [], errorDescription: "failed")
        XCTAssertNil(entry.startedAt)
        XCTAssertNil(entry.completedAt)
        XCTAssertNil(entry.totalBytes)
        XCTAssertNil(entry.averageBytesPerSecond())
        XCTAssertNil(entry.withMetrics(startedAt: .now, completedAt: .now.addingTimeInterval(-1), totalBytes: 100, transferredBytes: 100).averageBytesPerSecond())
    }

    func testFileSizeIncludesNestedAndHiddenFilesButDoesNotFollowSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 100).write(to: root.appendingPathComponent("a"))
        try Data(repeating: 0, count: 50).write(to: nested.appendingPathComponent(".hidden"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: nested)
        XCTAssertEqual(TransferFileSize.byteCount(of: [root]), 150)
        XCTAssertEqual(TransferFileSize.byteCount(of: [root.appendingPathComponent("a")]), 100)
        XCTAssertNil(TransferFileSize.byteCount(of: [root.appendingPathComponent("missing")]))
    }

    @MainActor
    func testCompletedUploadPersistsMeasuredSizeAndTimestamps() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("data.bin")
        try Data(repeating: 0, count: 1_024).write(to: file)
        let store = AsyncUploadHistoryStore(store: UploadHistoryStore(historyFileURL: root.appendingPathComponent("history.json")))
        let queue = TransferQueue(store: store, execute: { _, _ in
            .uploaded([UploadedFile(localURL: file, remoteDisplayPath: "~/data.bin")])
        }, copyPaths: { _ in true })
        queue.enqueue([.upload(target: SSHTarget(name: "host", source: .config), sources: [UploadSourceFile(sourceURL: file, remoteName: "data.bin")])])
        for _ in 0..<300 {
            if queue.activeCount == 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(queue.activeCount, 0)
        await queue.waitForPersistence()
        let saved = try await store.load()
        let completed = try XCTUnwrap(saved.first)
        XCTAssertEqual(completed.totalBytes, 1_024)
        XCTAssertEqual(completed.transferredBytes, 1_024)
        XCTAssertNotNil(completed.startedAt)
        XCTAssertNotNil(completed.completedAt)
        XCTAssertGreaterThan(try XCTUnwrap(completed.averageBytesPerSecond()), 0)
    }

    @MainActor
    func testCompletedDownloadMeasuresDestinationFileAndPersistsAverage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent("download.bin")
        let store = AsyncUploadHistoryStore(store: UploadHistoryStore(historyFileURL: root.appendingPathComponent("history.json")))
        let queue = TransferQueue(store: store, execute: { _, _ in
            try Data(repeating: 0, count: 2_048).write(to: destination)
            return .downloaded([DownloadedFile(remotePath: "~/download.bin", localURL: destination, localDisplayPath: destination.path, strategy: .rsyncFile)])
        }, copyPaths: { _ in true })
        queue.enqueue([.download(target: SSHTarget(name: "host", source: .config), paths: [RemotePath(hostHint: nil, path: "~/download.bin")])])
        for _ in 0..<300 {
            if queue.activeCount == 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(queue.activeCount, 0)
        await queue.waitForPersistence()
        let saved = try await store.load()
        let completed = try XCTUnwrap(saved.first)
        XCTAssertEqual(completed.direction, .download)
        XCTAssertEqual(completed.totalBytes, 2_048)
        XCTAssertEqual(completed.transferredBytes, 2_048)
        XCTAssertGreaterThan(try XCTUnwrap(completed.averageBytesPerSecond()), 0)
    }
}
