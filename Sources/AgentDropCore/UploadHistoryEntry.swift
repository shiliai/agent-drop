import Foundation

public enum TransferDirection: String, Codable, Equatable, Sendable {
    case upload
    case download
}

public struct UploadHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case running
        case succeeded
        case failed
        case cancelled
    }

    public let id: UUID
    public let createdAt: Date
    public let direction: TransferDirection
    public let targetName: String
    public let status: Status
    public let localFileNames: [String]
    public let remoteDisplayPaths: [String]
    public let localDisplayPaths: [String]
    public let errorMessage: String?
    public let progress: TransferProgress?
    public let retryRequest: TransferRequest?
    public let startedAt: Date?
    public let completedAt: Date?
    public let totalBytes: Int64?
    public let transferredBytes: Int64?
    public let duration: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case direction
        case targetName
        case status
        case localFileNames
        case remoteDisplayPaths
        case localDisplayPaths
        case errorMessage
        case progress
        case retryRequest
        case startedAt
        case completedAt
        case totalBytes
        case transferredBytes
        case duration
    }

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        direction: TransferDirection = .upload,
        targetName: String,
        status: Status,
        localFileNames: [String],
        remoteDisplayPaths: [String],
        localDisplayPaths: [String] = [],
        errorMessage: String?,
        progress: TransferProgress? = nil,
        retryRequest: TransferRequest? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        totalBytes: Int64? = nil,
        transferredBytes: Int64? = nil,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.direction = direction
        self.targetName = targetName
        self.status = status
        self.localFileNames = localFileNames
        self.remoteDisplayPaths = remoteDisplayPaths
        self.localDisplayPaths = localDisplayPaths
        self.errorMessage = errorMessage
        self.progress = progress
        self.retryRequest = retryRequest
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.totalBytes = totalBytes
        self.transferredBytes = transferredBytes
        self.duration = duration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        direction = try container.decodeIfPresent(TransferDirection.self, forKey: .direction) ?? .upload
        targetName = try container.decode(String.self, forKey: .targetName)
        status = try container.decode(Status.self, forKey: .status)
        localFileNames = try container.decode([String].self, forKey: .localFileNames)
        remoteDisplayPaths = try container.decode([String].self, forKey: .remoteDisplayPaths)
        localDisplayPaths = try container.decodeIfPresent([String].self, forKey: .localDisplayPaths) ?? []
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        progress = try container.decodeIfPresent(TransferProgress.self, forKey: .progress)
        retryRequest = try container.decodeIfPresent(TransferRequest.self, forKey: .retryRequest)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        totalBytes = try container.decodeIfPresent(Int64.self, forKey: .totalBytes)
        transferredBytes = try container.decodeIfPresent(Int64.self, forKey: .transferredBytes)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
    }

    public var copyPayload: String? {
        guard status == .succeeded else {
            return nil
        }

        switch direction {
        case .upload:
            guard !remoteDisplayPaths.isEmpty else { return nil }
            return remoteDisplayPaths.joined(separator: "\n")
        case .download:
            guard !localDisplayPaths.isEmpty else { return nil }
            return localDisplayPaths.joined(separator: "\n")
        }
    }

    public var resolvedRetryRequest: TransferRequest? {
        if let retryRequest { return retryRequest }
        guard direction == .download,
              let paths = try? RemotePathParser.parse(remoteDisplayPaths.joined(separator: "\n")) else { return nil }
        return .download(target: SSHTarget(name: targetName, source: .config), paths: paths)
    }

    public func updatingProgress(_ progress: TransferProgress?) -> UploadHistoryEntry {
        UploadHistoryEntry(
            id: id,
            createdAt: createdAt,
            direction: direction,
            targetName: targetName,
            status: status,
            localFileNames: localFileNames,
            remoteDisplayPaths: remoteDisplayPaths,
            localDisplayPaths: localDisplayPaths,
            errorMessage: errorMessage,
            progress: progress,
            retryRequest: retryRequest,
            startedAt: startedAt, completedAt: completedAt, totalBytes: totalBytes,
            transferredBytes: canMeasureLiveBytes && status == .running ? (progress?.completedBytes ?? transferredBytes) : transferredBytes,
            duration: duration
        )
    }

    public func withRetryRequest(_ request: TransferRequest) -> UploadHistoryEntry {
        UploadHistoryEntry(
            id: id, createdAt: createdAt, direction: direction, targetName: targetName,
            status: status, localFileNames: localFileNames, remoteDisplayPaths: remoteDisplayPaths,
            localDisplayPaths: localDisplayPaths, errorMessage: errorMessage, progress: progress,
            retryRequest: request,
            startedAt: startedAt, completedAt: completedAt, totalBytes: totalBytes, transferredBytes: transferredBytes, duration: duration
        )
    }

    public func withStatus(_ status: Status, errorMessage: String?) -> UploadHistoryEntry {
        UploadHistoryEntry(
            id: id, createdAt: createdAt, direction: direction, targetName: targetName,
            status: status, localFileNames: localFileNames, remoteDisplayPaths: remoteDisplayPaths,
            localDisplayPaths: localDisplayPaths, errorMessage: errorMessage, progress: progress,
            retryRequest: retryRequest, startedAt: startedAt, completedAt: completedAt,
            totalBytes: totalBytes, transferredBytes: transferredBytes, duration: duration
        )
    }

    public func withMetrics(startedAt: Date?, completedAt: Date? = nil, totalBytes: Int64?, transferredBytes: Int64? = nil) -> UploadHistoryEntry {
        UploadHistoryEntry(
            id: id, createdAt: createdAt, direction: direction, targetName: targetName, status: status,
            localFileNames: localFileNames, remoteDisplayPaths: remoteDisplayPaths, localDisplayPaths: localDisplayPaths,
            errorMessage: errorMessage, progress: progress, retryRequest: retryRequest,
            startedAt: startedAt, completedAt: completedAt, totalBytes: totalBytes, transferredBytes: transferredBytes,
            duration: startedAt.flatMap { start in completedAt.map { $0.timeIntervalSince(start) } }
        )
    }

    public func averageBytesPerSecond(now: Date = Date()) -> Double? {
        guard let startedAt, let transferredBytes, transferredBytes >= 0 else { return nil }
        let elapsed: TimeInterval
        if let completedAt {
            elapsed = duration ?? completedAt.timeIntervalSince(startedAt)
        } else {
            elapsed = now.timeIntervalSince(startedAt)
        }
        guard elapsed > 0, elapsed.isFinite else { return nil }
        return Double(transferredBytes) / elapsed
    }

    private var canMeasureLiveBytes: Bool {
        guard case let .upload(_, sources) = retryRequest else { return false }
        return sources.count == 1 && !sources[0].isDirectory
    }

    public static func shortErrorMessage(from message: String) -> String {
        UploadFeedbackFormatter.shortReason(from: message)
    }
}

public extension JSONEncoder {
    static var agentDropHistory: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var agentDropHistory: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public extension UploadHistoryEntry {
    static func uploadStarted(
        id: UUID = UUID(),
        targetName: String,
        fileURLs: [URL],
        createdAt: Date = Date()
    ) -> UploadHistoryEntry {
        UploadHistoryEntry(
            id: id,
            createdAt: createdAt,
            direction: .upload,
            targetName: targetName,
            status: .running,
            localFileNames: fileURLs.map(\.lastPathComponent),
            remoteDisplayPaths: [],
            localDisplayPaths: [],
            errorMessage: nil
        )
    }

    static func succeeded(
        targetName: String,
        uploadedFiles: [UploadedFile],
        createdAt: Date = Date(),
        id: UUID = UUID()
    ) -> UploadHistoryEntry {
        UploadHistoryEntry(
            id: id,
            createdAt: createdAt,
            direction: .upload,
            targetName: targetName,
            status: .succeeded,
            localFileNames: uploadedFiles.map(\.localDisplayName),
            remoteDisplayPaths: uploadedFiles.map(\.remoteDisplayPath),
            localDisplayPaths: [],
            errorMessage: nil
        )
    }

    static func failed(
        targetName: String,
        fileURLs: [URL],
        errorDescription: String,
        createdAt: Date = Date(),
        id: UUID = UUID()
    ) -> UploadHistoryEntry {
        UploadHistoryEntry(
            id: id,
            createdAt: createdAt,
            direction: .upload,
            targetName: targetName,
            status: .failed,
            localFileNames: fileURLs.map(\.lastPathComponent),
            remoteDisplayPaths: [],
            localDisplayPaths: [],
            errorMessage: shortErrorMessage(from: errorDescription)
        )
    }

    static func downloadSucceeded(
        targetName: String,
        downloadedFiles: [DownloadedFile],
        createdAt: Date = Date(),
        id: UUID = UUID()
    ) -> UploadHistoryEntry {
        UploadHistoryEntry(
            id: id,
            createdAt: createdAt,
            direction: .download,
            targetName: targetName,
            status: .succeeded,
            localFileNames: downloadedFiles.map { $0.localURL.lastPathComponent },
            remoteDisplayPaths: downloadedFiles.map(\.remotePath),
            localDisplayPaths: downloadedFiles.map(\.localDisplayPath),
            errorMessage: nil
        )
    }

    static func downloadFailed(
        targetName: String,
        remotePaths: [String],
        errorDescription: String,
        createdAt: Date = Date(),
        id: UUID = UUID()
    ) -> UploadHistoryEntry {
        UploadHistoryEntry(
            id: id,
            createdAt: createdAt,
            direction: .download,
            targetName: targetName,
            status: .failed,
            localFileNames: [],
            remoteDisplayPaths: remotePaths,
            localDisplayPaths: [],
            errorMessage: shortErrorMessage(from: errorDescription)
        )
    }

    static func downloadFailed(
        targetName: String,
        remotePaths: [RemotePath],
        errorDescription: String,
        createdAt: Date = Date(),
        id: UUID = UUID()
    ) -> UploadHistoryEntry {
        downloadFailed(
            targetName: targetName,
            remotePaths: remotePaths.map(\.path),
            errorDescription: errorDescription,
            createdAt: createdAt,
            id: id
        )
    }
}
