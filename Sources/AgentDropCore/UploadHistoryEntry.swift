import Foundation

public struct UploadHistoryEntry: Codable, Equatable, Identifiable {
    public enum Status: String, Codable, Equatable {
        case succeeded
        case failed
    }

    public let id: UUID
    public let createdAt: Date
    public let targetName: String
    public let status: Status
    public let localFileNames: [String]
    public let remoteDisplayPaths: [String]
    public let errorMessage: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        targetName: String,
        status: Status,
        localFileNames: [String],
        remoteDisplayPaths: [String],
        errorMessage: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.targetName = targetName
        self.status = status
        self.localFileNames = localFileNames
        self.remoteDisplayPaths = remoteDisplayPaths
        self.errorMessage = errorMessage
    }

    public var copyPayload: String? {
        guard status == .succeeded, !remoteDisplayPaths.isEmpty else {
            return nil
        }
        return remoteDisplayPaths.joined(separator: "\n")
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
            targetName: targetName,
            status: .succeeded,
            localFileNames: uploadedFiles.map(\.localDisplayName),
            remoteDisplayPaths: uploadedFiles.map(\.remoteDisplayPath),
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
            targetName: targetName,
            status: .failed,
            localFileNames: fileURLs.map(\.lastPathComponent),
            remoteDisplayPaths: [],
            errorMessage: shortErrorMessage(from: errorDescription)
        )
    }
}
