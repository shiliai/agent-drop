import XCTest
@testable import AgentDropCore

final class TransferQueueTests: XCTestCase {
    @MainActor
    func testConcurrentTransfersKeepIndependentProgressAndBoundConcurrency() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let executor = ControlledExecutor()
        defer { executor.releaseAll() }
        let queue = TransferQueue(store: fixture.store, concurrencyLimit: 2, execute: executor.execute, copyPaths: { _ in true })
        let requests = [upload("a", host: "alpha"), download("b", host: "beta"), upload("c", host: "gamma")]
        let ids = queue.enqueue(requests)
        try await eventually { executor.startedCount == 2 }

        XCTAssertEqual(queue.activeCount, 3)
        XCTAssertEqual(queue.pendingIDs, [ids[2]])
        XCTAssertNotNil(queue.entries.first { $0.id == ids[0] }?.startedAt)
        XCTAssertNil(queue.entries.first { $0.id == ids[2] }?.startedAt)
        executor.report(requests[0], fraction: 0.25)
        executor.report(requests[1], fraction: 0.75)
        try await eventually {
            queue.entries.first { $0.id == ids[0] }?.progress?.fractionCompleted == 0.25
                && queue.entries.first { $0.id == ids[1] }?.progress?.fractionCompleted == 0.75
        }
        XCTAssertNil(queue.entries.first { $0.id == ids[2] }?.progress)
        executor.releaseAll()
        try await eventually { queue.activeCount == 0 }
        XCTAssertEqual(queue.entries.filter { $0.status == .succeeded }.count, 3)
        await queue.waitForPersistence()
        let saved = try await fixture.store.load()
        XCTAssertEqual(saved.count, 3)
        XCTAssertTrue(saved.allSatisfy { $0.status == .succeeded && $0.progress == nil })
    }

    @MainActor
    func testRetryPreservesOriginalRequestAndCannotBeSubmittedTwiceWhileRunning() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let executor = ControlledExecutor()
        defer { executor.releaseAll() }
        let queue = TransferQueue(store: fixture.store, execute: executor.execute, copyPaths: { _ in true })
        let originalRequest = upload("folder with spaces", host: "original-host", isDirectory: true)
        let failed = originalRequest.entry(id: UUID(), createdAt: Date(timeIntervalSince1970: 10), status: .failed, error: "Connection lost")

        let retryID = try XCTUnwrap(queue.retry(failed))
        XCTAssertNotEqual(retryID, failed.id)
        XCTAssertNil(queue.retry(failed))
        try await eventually { executor.startedCount == 1 }
        XCTAssertEqual(executor.requests, [originalRequest])
        XCTAssertEqual(queue.entries.first?.retryRequest, originalRequest)
        XCTAssertEqual(queue.entries.first?.progress, nil)
        XCTAssertTrue(queue.retryingIDs.contains(failed.id))
        executor.releaseAll()
        try await eventually { queue.activeCount == 0 }
        XCTAssertFalse(queue.retryingIDs.contains(failed.id))
        await queue.waitForPersistence()
    }

    @MainActor
    func testCancelRunningTransferTerminatesExecutorAndMakesItRetryable() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let executor = CancellationAwareExecutor()
        let queue = TransferQueue(
            store: fixture.store,
            executeWithCancellation: executor.execute,
            copyPaths: { _ in true }
        )
        let request = download("large.bin")
        let id = try XCTUnwrap(queue.enqueue([request]).first)
        try await eventually { executor.started }

        queue.cancel(try XCTUnwrap(queue.entries.first))
        try await eventually { queue.entries.first?.status == .cancelled }
        XCTAssertTrue(queue.canRetry(try XCTUnwrap(queue.entries.first)))
        XCTAssertEqual(queue.entries.first?.errorMessage, "Transfer cancelled by user.")
        await queue.waitForPersistence()
        let saved = try await fixture.store.load()
        XCTAssertEqual(saved.first(where: { $0.id == id })?.status, .cancelled)
    }

    @MainActor
    func testFailedItemDoesNotLoseSuccessfulSiblingsAndBatchCopiesAllSuccessfulPathsOnce() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var copied: [String] = []
        let queue = TransferQueue(store: fixture.store, execute: { request, progress in
            progress(TransferProgress(completedBytes: 10, fractionCompleted: 0.5, bytesPerSecond: 20, estimatedTimeRemaining: 1))
            if request.target.name == "bad-host" { throw UploadError.rsyncFailed("Connection lost") }
            return ControlledExecutor.result(for: request)
        }, copyPaths: { copied.append($0); return true })
        let ids = queue.enqueue([upload("a"), upload("b", host: "bad-host"), upload("c")])
        try await eventually { queue.activeCount == 0 }
        XCTAssertEqual(queue.entries.first { $0.id == ids[0] }?.status, .succeeded)
        let failed = try XCTUnwrap(queue.entries.first { $0.id == ids[1] })
        XCTAssertEqual(failed.status, .failed)
        XCTAssertTrue(queue.canRetry(failed))
        XCTAssertEqual(copied, ["~/inbox/a\n~/inbox/c"])
        await queue.waitForPersistence()
        let saved = try await fixture.store.load()
        XCTAssertEqual(saved.filter { $0.status == .failed }.count, 1)
        XCTAssertFalse(saved.contains { $0.status == .running })
    }

    @MainActor
    func testLateProgressCannotResurrectCompletedTransferOrOverwritePersistedTerminalState() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let executor = ControlledExecutor()
        let queue = TransferQueue(store: fixture.store, execute: executor.execute, copyPaths: { _ in true })
        let request = download("report.txt")
        queue.enqueue([request])
        try await eventually { executor.startedCount == 1 }
        executor.report(request, fraction: 0.1)
        executor.releaseAll()
        try await eventually { queue.activeCount == 0 }
        executor.report(request, fraction: 0.2)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(queue.entries.first?.progress)
        XCTAssertEqual(queue.entries.first?.status, .succeeded)
        await queue.waitForPersistence()
        let saved = try await fixture.store.load()
        XCTAssertEqual(saved.first?.status, .succeeded)
        XCTAssertNil(saved.first?.progress)
    }

    @MainActor
    func testLocalSnapshotsOverrideStaleHistoryWithoutHidingOtherProcesses() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let executor = ControlledExecutor()
        defer { executor.releaseAll() }
        let queue = TransferQueue(store: fixture.store, execute: executor.execute, copyPaths: { _ in true })
        queue.enqueue([upload("local")])
        let local = try XCTUnwrap(queue.entries.first)
        let external = upload("finder").entry(id: UUID(), createdAt: Date(), status: .running)
        let stale = local.updatingProgress(TransferProgress(completedBytes: 99, fractionCompleted: 0.99, bytesPerSecond: nil, estimatedTimeRemaining: nil))
        let merged = queue.mergedEntries(with: [stale, external])
        XCTAssertEqual(merged.count, 2)
        XCTAssertNil(merged.first { $0.id == local.id }?.progress)
        XCTAssertTrue(merged.contains(external))
        executor.releaseAll()
        try await eventually { queue.activeCount == 0 }
        await queue.waitForPersistence()
    }

    func testRetryMetadataRoundTripsForUploadDirectoriesAndHostHintedDownloads() throws {
        for request in [upload("folder with spaces", isDirectory: true), download("report with spaces.txt")] {
            let entry = request.entry(id: UUID(), createdAt: Date(timeIntervalSince1970: 12), status: .failed, error: "Disconnected")
            let decoded = try JSONDecoder.agentDropHistory.decode(UploadHistoryEntry.self, from: JSONEncoder.agentDropHistory.encode(entry))
            XCTAssertEqual(decoded, entry)
            XCTAssertEqual(decoded.retryRequest, request)
            XCTAssertEqual(decoded.updatingProgress(nil).retryRequest, request)
        }
    }

    @MainActor
    func testLegacyFailureWithoutSourceMetadataCannotGuessRetryPaths() throws {
        let queue = TransferQueue()
        let entry = UploadHistoryEntry.failed(targetName: "host", fileURLs: [URL(fileURLWithPath: "/tmp/a")], errorDescription: "failed")
        XCTAssertFalse(queue.canRetry(entry))
        XCTAssertNil(queue.retry(entry))
    }

    @MainActor
    func testPersistenceErrorDoesNotTurnSuccessfulTransferIntoRetryableFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not a directory".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = TransferQueue(
            store: AsyncUploadHistoryStore(store: UploadHistoryStore(historyFileURL: root.appendingPathComponent("history.json"))),
            execute: { request, _ in ControlledExecutor.result(for: request) }, copyPaths: { _ in true }
        )
        queue.enqueue([upload("a")])
        try await eventually { queue.activeCount == 0 }
        await queue.waitForPersistence()
        XCTAssertNotNil(queue.persistenceError)
        XCTAssertEqual(queue.entries.first?.status, .succeeded)
        XCTAssertFalse(queue.canRetry(try XCTUnwrap(queue.entries.first)))
    }

    func testLegacyDownloadCanRecoverRetryRequestFromSavedRemotePaths() throws {
        let failed = UploadHistoryEntry.downloadFailed(
            targetName: "original-host", remotePaths: ["~/folder with spaces/report.txt", "/var/log/build.log"],
            errorDescription: "Connection lost"
        )
        let data = try JSONEncoder.agentDropHistory.encode(failed)
        let decoded = try JSONDecoder.agentDropHistory.decode(UploadHistoryEntry.self, from: data)
        XCTAssertNil(decoded.retryRequest)
        XCTAssertEqual(decoded.resolvedRetryRequest, .download(
            target: SSHTarget(name: "original-host", source: .config),
            paths: [RemotePath(hostHint: nil, path: "~/folder with spaces/report.txt"), RemotePath(hostHint: nil, path: "/var/log/build.log")]
        ))
    }

    func testLegacyDownloadWithUnsupportedPathCannotBeRetried() {
        let failed = UploadHistoryEntry.downloadFailed(targetName: "host", remotePaths: ["relative.txt"], errorDescription: "failed")
        XCTAssertNil(failed.resolvedRetryRequest)
    }

    private func upload(_ name: String, host: String = "host", isDirectory: Bool = false) -> TransferRequest {
        .upload(target: SSHTarget(name: host, source: .config), sources: [
            UploadSourceFile(sourceURL: URL(fileURLWithPath: "/tmp/\(name)"), remoteName: name, isDirectory: isDirectory)
        ])
    }

    private func download(_ name: String, host: String = "host") -> TransferRequest {
        .download(target: SSHTarget(name: host, source: .config), paths: [RemotePath(hostHint: host, path: "~/\(name)")])
    }

    @MainActor
    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for transfer state")
    }
}

private struct Fixture {
    let root: URL
    let store: AsyncUploadHistoryStore

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = AsyncUploadHistoryStore(store: UploadHistoryStore(historyFileURL: root.appendingPathComponent("history.json")))
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

private final class ControlledExecutor: @unchecked Sendable {
    private let condition = NSCondition()
    private var released = false
    private var starts: [TransferRequest] = []
    private var callbacks: [(TransferRequest, TransferProgressHandler)] = []

    var startedCount: Int { condition.withLock { starts.count } }
    var requests: [TransferRequest] { condition.withLock { starts } }

    func execute(_ request: TransferRequest, progress: @escaping TransferProgressHandler) throws -> TransferResult {
        condition.lock()
        starts.append(request)
        callbacks.append((request, progress))
        while !released { condition.wait() }
        condition.unlock()
        return Self.result(for: request)
    }

    func report(_ request: TransferRequest, fraction: Double) {
        let callback = condition.withLock { callbacks.first { $0.0 == request }?.1 }
        callback?(TransferProgress(completedBytes: 10, fractionCompleted: fraction, bytesPerSecond: 100, estimatedTimeRemaining: 1))
    }

    func releaseAll() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }

    static func result(for request: TransferRequest) -> TransferResult {
        switch request {
        case let .upload(_, sources):
            return .uploaded(sources.map { UploadedFile(localURL: $0.sourceURL, remoteDisplayPath: "~/inbox/\($0.remoteName)") })
        case let .download(_, paths):
            return .downloaded(paths.map {
                DownloadedFile(remotePath: $0.path, localURL: URL(fileURLWithPath: "/tmp/download"), localDisplayPath: "/tmp/download", strategy: .rsyncFile)
            })
        }
    }
}

private final class CancellationAwareExecutor: @unchecked Sendable {
    private let lock = NSLock()
    private var startedValue = false

    var started: Bool { lock.withLock { startedValue } }

    func execute(
        _ request: TransferRequest,
        progress: @escaping TransferProgressHandler,
        cancellation: TransferCancellation?
    ) throws -> TransferResult {
        lock.withLock { startedValue = true }
        while cancellation?.isCancelled != true {
            Thread.sleep(forTimeInterval: 0.01)
        }
        throw UploadError.rsyncFailed("terminated")
    }
}

private extension NSCondition {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
