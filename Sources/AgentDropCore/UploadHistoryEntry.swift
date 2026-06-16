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
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 120 else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 117)
        return String(trimmed[..<end]) + "..."
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
