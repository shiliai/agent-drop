import Foundation
import Darwin

public final class UploadHistoryStore: @unchecked Sendable {
    private static let finderExtensionContainerPath = "/Library/Containers/ai.shili.AgentDrop.FinderSync/Data"
    // Same-process coordination for multiple store instances sharing one history path.
    private static let coordinatorRegistry = QueueRegistry()
    private let historyFileURL: URL
    private let limit: Int
    private let fileManager: FileManager
    private let coordinator: DispatchQueue
    private let lockFileURL: URL

    public init(
        historyFileURL: URL = UploadHistoryStore.defaultHistoryFileURL(),
        limit: Int = 100,
        fileManager: FileManager = .default
    ) {
        self.historyFileURL = historyFileURL
        self.limit = limit
        self.fileManager = fileManager
        self.coordinator = Self.coordinator(for: historyFileURL)
        self.lockFileURL = historyFileURL.deletingLastPathComponent()
            .appendingPathComponent(".upload-history.lock", isDirectory: false)
    }

    public static func defaultHistoryFileURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let baseDirectory = home.path.hasSuffix(finderExtensionContainerPath)
            ? home
            : home.appendingPathComponent(
                "Library/Containers/ai.shili.AgentDrop.FinderSync/Data",
                isDirectory: true
            )

        return baseDirectory
            .appendingPathComponent("Library/Application Support/Agent Drop", isDirectory: true)
            .appendingPathComponent("upload-history.json", isDirectory: false)
    }

    public func load() throws -> [UploadHistoryEntry] {
        try coordinator.sync {
            try withProcessLock {
                try loadUnlocked()
            }
        }
    }

    public func append(_ entry: UploadHistoryEntry) throws {
        try coordinator.sync {
            try withProcessLock {
                var entries = try loadUnlocked()
                entries.insert(entry, at: 0)
                try write(sortedAndTrimmed(entries))
            }
        }
    }

    public func upsert(_ entry: UploadHistoryEntry) throws {
        try coordinator.sync {
            try withProcessLock {
                var entries = try loadUnlocked()
                if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                    entries[index] = entry
                } else {
                    entries.insert(entry, at: 0)
                }
                try write(sortedAndTrimmed(entries))
            }
        }
    }

    private static func coordinator(for historyFileURL: URL) -> DispatchQueue {
        let path = canonicalQueueKey(for: historyFileURL)
        return coordinatorRegistry.queue(forPath: path)
    }

    private static func canonicalQueueKey(for historyFileURL: URL) -> String {
        historyFileURL.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func loadUnlocked() throws -> [UploadHistoryEntry] {
        guard fileManager.fileExists(atPath: historyFileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: historyFileURL)
        do {
            let entries = try JSONDecoder.agentDropHistory.decode([UploadHistoryEntry].self, from: data)
            return sortedAndTrimmed(entries)
        } catch is DecodingError {
            try preserveCorruptHistory()
            try write([])
            return []
        }
    }

    private func sortedAndTrimmed(_ entries: [UploadHistoryEntry]) -> [UploadHistoryEntry] {
        Array(entries.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }

    private func write(_ entries: [UploadHistoryEntry]) throws {
        let directory = historyFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.agentDropHistory.encode(entries)
        try data.write(to: historyFileURL, options: [.atomic])
    }

    private func preserveCorruptHistory() throws {
        guard fileManager.fileExists(atPath: historyFileURL.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let corruptURL = historyFileURL.deletingLastPathComponent()
            .appendingPathComponent("\(historyFileURL.lastPathComponent).corrupt-\(stamp)")
        try? fileManager.removeItem(at: corruptURL)
        try fileManager.moveItem(at: historyFileURL, to: corruptURL)
    }

    private func withProcessLock<T>(_ operation: () throws -> T) throws -> T {
        let directory = lockFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: lockFileURL.path) {
            let created = fileManager.createFile(atPath: lockFileURL.path, contents: nil)
            if !created && !fileManager.fileExists(atPath: lockFileURL.path) {
                throw CocoaError(.fileWriteUnknown)
            }
        }

        let fileDescriptor = open(lockFileURL.path, O_RDWR)
        guard fileDescriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer {
            close(fileDescriptor)
        }

        guard flock(fileDescriptor, LOCK_EX) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer {
            flock(fileDescriptor, LOCK_UN)
        }

        return try operation()
    }
}

private final class QueueRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var queuesByPath: [String: DispatchQueue] = [:]

    func queue(forPath path: String) -> DispatchQueue {
        lock.lock()
        defer { lock.unlock() }

        if let existing = queuesByPath[path] {
            return existing
        }

        let queue = DispatchQueue(label: "ai.shili.AgentDrop.UploadHistoryStore.\(path)")
        queuesByPath[path] = queue
        return queue
    }
}
