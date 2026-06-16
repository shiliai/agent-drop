import Foundation

public final class UploadHistoryStore {
    private let historyFileURL: URL
    private let limit: Int
    private let fileManager: FileManager

    public init(
        historyFileURL: URL = UploadHistoryStore.defaultHistoryFileURL(),
        limit: Int = 100,
        fileManager: FileManager = .default
    ) {
        self.historyFileURL = historyFileURL
        self.limit = limit
        self.fileManager = fileManager
    }

    public static func defaultHistoryFileURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent("Library/Containers/ai.shili.AgentDrop.FinderSync/Data/Library/Application Support/Agent Drop", isDirectory: true)
            .appendingPathComponent("upload-history.json", isDirectory: false)
    }

    public func load() throws -> [UploadHistoryEntry] {
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

    public func append(_ entry: UploadHistoryEntry) throws {
        var entries = try load()
        entries.insert(entry, at: 0)
        try write(sortedAndTrimmed(entries))
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
}
