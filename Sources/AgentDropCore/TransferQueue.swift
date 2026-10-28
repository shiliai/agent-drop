import Foundation
import Observation

public enum TransferRequest: Codable, Equatable, Sendable {
    case upload(target: SSHTarget, sources: [UploadSourceFile])
    case download(target: SSHTarget, paths: [RemotePath])

    public var target: SSHTarget {
        switch self {
        case let .upload(target, _), let .download(target, _): return target
        }
    }

    public func entry(id: UUID, createdAt: Date, status: UploadHistoryEntry.Status, error: String? = nil) -> UploadHistoryEntry {
        switch self {
        case let .upload(target, sources):
            return UploadHistoryEntry(
                id: id, createdAt: createdAt, targetName: target.name, status: status,
                localFileNames: sources.map(\.localDisplayName), remoteDisplayPaths: [],
                localDisplayPaths: sources.map { $0.sourceURL.path }, errorMessage: error, retryRequest: self
            )
        case let .download(target, paths):
            return UploadHistoryEntry(
                id: id, createdAt: createdAt, direction: .download, targetName: target.name,
                status: status, localFileNames: paths.map { ($0.path as NSString).lastPathComponent },
                remoteDisplayPaths: paths.map(\.path), errorMessage: error, retryRequest: self
            )
        }
    }
}

public enum TransferResult: Sendable {
    case uploaded([UploadedFile])
    case downloaded([DownloadedFile])

    public static func execute(_ request: TransferRequest, progress: @escaping TransferProgressHandler) throws -> TransferResult {
        try execute(request, progress: progress, cancellation: nil)
    }

    public static func execute(
        _ request: TransferRequest,
        progress: @escaping TransferProgressHandler,
        cancellation: TransferCancellation?
    ) throws -> TransferResult {
        switch request {
        case let .upload(target, sources):
            let uploaded = try UploadService().upload(sources: sources, target: target, copyToClipboard: false, progress: progress, cancellation: cancellation)
            for source in sources { ClipboardImageStager.cleanupAfterSuccessfulUpload(source.sourceURL) }
            return .uploaded(uploaded)
        case let .download(target, paths):
            return .downloaded(try DownloadService().download(remotePaths: paths, target: target, copyToClipboard: false, progress: progress, cancellation: cancellation))
        }
    }
}

@MainActor @Observable
public final class TransferQueue {
    public private(set) var entries: [UploadHistoryEntry] = []
    public private(set) var pendingIDs: [UUID] = []
    public private(set) var retryingIDs: Set<UUID> = []
    public private(set) var persistenceError: String?
    public private(set) var statusSummary = TransferStatusSummary.idle

    @ObservationIgnored private let store: AsyncUploadHistoryStore
    @ObservationIgnored private let execute: @Sendable (TransferRequest, @escaping TransferProgressHandler, TransferCancellation?) throws -> TransferResult
    @ObservationIgnored private let copyPaths: @MainActor (String) -> Bool
    @ObservationIgnored private let concurrencyLimit: Int
    @ObservationIgnored private var runningIDs: Set<UUID> = []
    @ObservationIgnored private var retryOrigins: [UUID: UUID] = [:]
    @ObservationIgnored private var batches: [[UUID]] = []
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
    @ObservationIgnored private var progressSavedAt: [UUID: Date] = [:]
    @ObservationIgnored private var cancellations: [UUID: TransferCancellation] = [:]
    @ObservationIgnored private var cancelRequestedIDs: Set<UUID> = []

    private init(
        store: AsyncUploadHistoryStore = AsyncUploadHistoryStore(),
        concurrencyLimit: Int = 3,
        executor: @escaping @Sendable (TransferRequest, @escaping TransferProgressHandler, TransferCancellation?) throws -> TransferResult,
        copyPaths: @escaping @MainActor (String) -> Bool = { payload in
            (try? PBClipboardWriter().write(payload)) != nil
        }
    ) {
        self.store = store
        self.concurrencyLimit = max(1, concurrencyLimit)
        self.execute = executor
        self.copyPaths = copyPaths
    }

    public convenience init(
        store: AsyncUploadHistoryStore = AsyncUploadHistoryStore(),
        concurrencyLimit: Int = 3,
        execute: @escaping @Sendable (TransferRequest, @escaping TransferProgressHandler) throws -> TransferResult,
        copyPaths: @escaping @MainActor (String) -> Bool = { payload in
            (try? PBClipboardWriter().write(payload)) != nil
        }
    ) {
        self.init(store: store, concurrencyLimit: concurrencyLimit, executor: { request, progress, _ in
            try execute(request, progress)
        }, copyPaths: copyPaths)
    }

    public convenience init(
        store: AsyncUploadHistoryStore = AsyncUploadHistoryStore(),
        concurrencyLimit: Int = 3,
        executeWithCancellation: @escaping @Sendable (TransferRequest, @escaping TransferProgressHandler, TransferCancellation?) throws -> TransferResult,
        copyPaths: @escaping @MainActor (String) -> Bool = { payload in
            (try? PBClipboardWriter().write(payload)) != nil
        }
    ) {
        self.init(store: store, concurrencyLimit: concurrencyLimit, executor: executeWithCancellation, copyPaths: copyPaths)
    }

    public convenience init(
        store: AsyncUploadHistoryStore = AsyncUploadHistoryStore(),
        concurrencyLimit: Int = 3,
        copyPaths: @escaping @MainActor (String) -> Bool = { payload in
            (try? PBClipboardWriter().write(payload)) != nil
        }
    ) {
        self.init(store: store, concurrencyLimit: concurrencyLimit, executor: TransferResult.execute, copyPaths: copyPaths)
    }

    public var activeCount: Int { entries.filter { $0.status == .running }.count }

    public func mergedEntries(with history: [UploadHistoryEntry]) -> [UploadHistoryEntry] {
        let localIDs = Set(entries.map(\.id))
        return (entries + history.filter { !localIDs.contains($0.id) }).sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    public func enqueue(_ requests: [TransferRequest]) -> [UUID] {
        let newEntries = requests.map { $0.entry(id: UUID(), createdAt: Date(), status: .running) }
        entries.insert(contentsOf: newEntries, at: 0)
        let ids = newEntries.map(\.id)
        pendingIDs.append(contentsOf: ids)
        if !ids.isEmpty { batches.append(ids) }
        for entry in newEntries { persist(entry) }
        startPending()
        return ids
    }

    public func canRetry(_ entry: UploadHistoryEntry) -> Bool {
        (entry.status == .failed || entry.status == .cancelled)
            && entry.resolvedRetryRequest != nil
            && !retryingIDs.contains(entry.id)
    }

    @discardableResult
    public func retry(_ entry: UploadHistoryEntry) -> UUID? {
        guard canRetry(entry), let request = entry.resolvedRetryRequest else { return nil }
        retryingIDs.insert(entry.id)
        let id = enqueue([request])[0]
        retryOrigins[id] = entry.id
        return id
    }

    public func cancel(_ entry: UploadHistoryEntry) {
        guard entry.status == .running else { return }
        if let index = entries.firstIndex(where: { $0.id == entry.id }), pendingIDs.contains(entry.id) {
            pendingIDs.removeAll { $0 == entry.id }
            let cancelled = entries[index]
                .withStatus(.cancelled, errorMessage: "Transfer cancelled by user.")
                .withMetrics(
                    startedAt: entries[index].startedAt,
                    completedAt: Date(),
                    totalBytes: entries[index].totalBytes,
                    transferredBytes: entries[index].transferredBytes
                )
            entries[index] = cancelled
            persist(cancelled)
            finishBatches()
            startPending()
            return
        }
        guard runningIDs.contains(entry.id) else { return }
        cancelRequestedIDs.insert(entry.id)
        cancellations[entry.id]?.cancel()
    }

    public func waitForPersistence() async {
        await persistenceTask?.value
    }

    private func startPending() {
        while runningIDs.count < concurrencyLimit, !pendingIDs.isEmpty {
            let id = pendingIDs.removeFirst()
            guard let index = entries.firstIndex(where: { $0.id == id }), let request = entries[index].retryRequest else { continue }
            let entry = entries[index].withMetrics(startedAt: Date(), totalBytes: nil)
            entries[index] = entry
            persist(entry)
            runningIDs.insert(id)
            let cancellation = TransferCancellation()
            cancellations[id] = cancellation
            statusSummary = .progress("\(activeCount) transfers active")
            let execute = self.execute
            Task {
                let outcome = await Task.detached(priority: .userInitiated) {
                    let sourceSize: Int64?
                    if case let .upload(_, sources) = request {
                        sourceSize = TransferFileSize.byteCount(of: sources.map(\.sourceURL))
                        await self.setTotalBytes(sourceSize, id: id)
                    } else { sourceSize = nil }
                    let result = Result {
                        try execute(request, { progress in
                            Task { @MainActor in self.updateProgress(progress, id: id) }
                        }, cancellation)
                    }
                    let completedAt = Date()
                    if case let .success(.downloaded(files)) = result {
                        return (result, TransferFileSize.byteCount(of: files.map(\.localURL)), completedAt)
                    }
                    return (result, sourceSize, completedAt)
                }.value
                finish(outcome.0, entry: entry, request: request, totalBytes: outcome.1, completedAt: outcome.2)
            }
        }
    }

    private func setTotalBytes(_ totalBytes: Int64?, id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }), runningIDs.contains(id) else { return }
        let entry = entries[index]
        entries[index] = entry.withMetrics(startedAt: entry.startedAt, totalBytes: totalBytes, transferredBytes: entry.transferredBytes)
        persist(entries[index])
    }

    private func updateProgress(_ progress: TransferProgress, id: UUID) {
        guard runningIDs.contains(id), let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index] = entries[index].updatingProgress(progress)
        let now = Date()
        if now.timeIntervalSince(progressSavedAt[id] ?? .distantPast) >= 0.3 {
            progressSavedAt[id] = now
            persist(entries[index])
        }
    }

    private func finish(_ result: Result<TransferResult, Error>, entry: UploadHistoryEntry, request: TransferRequest, totalBytes: Int64?, completedAt: Date) {
        let completed: UploadHistoryEntry
        if cancelRequestedIDs.contains(entry.id) {
            completed = request.entry(id: entry.id, createdAt: entry.createdAt, status: .cancelled, error: "Transfer cancelled by user.")
        } else {
            switch result {
            case let .success(.uploaded(files)):
                completed = .succeeded(targetName: entry.targetName, uploadedFiles: files, createdAt: entry.createdAt, id: entry.id)
            case let .success(.downloaded(files)):
                completed = .downloadSucceeded(targetName: entry.targetName, downloadedFiles: files, createdAt: entry.createdAt, id: entry.id)
            case let .failure(error):
                completed = request.entry(id: entry.id, createdAt: entry.createdAt, status: .failed, error: CLIErrorFormatter.message(for: error))
            }
        }
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            let bytes = completed.status == .succeeded ? totalBytes : entries[index].transferredBytes
            entries[index] = completed.withRetryRequest(request).withMetrics(
                startedAt: entry.startedAt, completedAt: completedAt, totalBytes: totalBytes, transferredBytes: bytes
            )
            persist(entries[index])
        }
        runningIDs.remove(entry.id)
        cancellations.removeValue(forKey: entry.id)
        cancelRequestedIDs.remove(entry.id)
        progressSavedAt[entry.id] = nil
        if let origin = retryOrigins.removeValue(forKey: entry.id) { retryingIDs.remove(origin) }
        finishBatches()
        startPending()
        if activeCount > 0 { statusSummary = .progress("\(activeCount) transfers active") }
    }

    private func finishBatches() {
        batches.removeAll { ids in
            let batch = ids.compactMap { id in entries.first { $0.id == id } }
            guard batch.allSatisfy({ $0.status != .running }) else { return false }
            let successful = batch.filter { $0.status == .succeeded }
            let payload = successful.compactMap(\.copyPayload).joined(separator: "\n")
            let copied = !payload.isEmpty && copyPaths(payload)
            let failed = batch.filter { $0.status == .failed }.count
            let cancelled = batch.filter { $0.status == .cancelled }.count
            if failed > 0 || cancelled > 0 {
                let parts = [
                    failed > 0 ? "\(failed) failed" : nil,
                    cancelled > 0 ? "\(cancelled) cancelled" : nil,
                    successful.isEmpty ? nil : "\(successful.count) completed"
                ].compactMap { $0 }.joined(separator: ", ")
                statusSummary = .failure(parts + ".")
            } else {
                statusSummary = copied ? .success("\(batch.count) transfers completed. Paths copied.")
                    : .failure("Transfers completed, but paths could not be copied. Copy them from History.")
            }
            return true
        }
    }

    private func persist(_ entry: UploadHistoryEntry) {
        // Chain writes so a delayed progress snapshot cannot replace a terminal state.
        let previous = persistenceTask
        let store = self.store
        persistenceTask = Task {
            await previous?.value
            do {
                try await store.upsert(entry)
            } catch {
                persistenceError = "Could not save transfer history: \(CLIErrorFormatter.message(for: error))"
            }
        }
    }
}
