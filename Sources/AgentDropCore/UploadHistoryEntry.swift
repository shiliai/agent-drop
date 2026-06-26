import Foundation

public enum TransferDirection: String, Codable, Equatable, Sendable {
    case upload
    case download
}

public struct UploadHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case succeeded
        case failed
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
        errorMessage: String?
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
