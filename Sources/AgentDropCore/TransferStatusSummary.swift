import Foundation

public enum TransferStatusSummary: Equatable, Sendable {
    case idle
    case progress(String)
    case success(String)
    case uploadSuccess(fileCount: Int, targetName: String, copiedPaths: Bool)
    case failure(String)

    public var systemImageName: String {
        switch self {
        case .idle:
            return "circle.fill"
        case .progress:
            return "arrow.up.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case let .uploadSuccess(_, _, copiedPaths):
            return copiedPaths ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        case .failure:
            return "xmark.circle.fill"
        }
    }

    public func statusText(
        lastUpdatedAt: Date?,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        switch self {
        case .idle:
            guard let lastUpdatedAt else {
                return "Last updated: never"
            }
            var formatStyle = Date.FormatStyle(date: .omitted, time: .standard)
            formatStyle.timeZone = timeZone
            return "Last updated: \(lastUpdatedAt.formatted(formatStyle))"
        case let .progress(message):
            return message
        case let .success(message):
            return message
        case let .uploadSuccess(fileCount, targetName, copiedPaths):
            return UploadFeedbackFormatter.success(
                fileCount: fileCount,
                targetName: targetName,
                copiedPaths: copiedPaths
            )
        case let .failure(message):
            return message
        }
    }
}

public extension TransferStatusSummary {
    static let defaultRunningHistoryStaleInterval: TimeInterval = 30 * 60

    static func runningUploadHistoryStatus(
        from entries: [UploadHistoryEntry],
        now: Date = Date(),
        staleAfter: TimeInterval = defaultRunningHistoryStaleInterval
    ) -> TransferStatusSummary? {
        guard let entry = entries
            .filter({ $0.direction == .upload && $0.status == .running })
            .sorted(by: { $0.createdAt > $1.createdAt })
            .first(where: { now.timeIntervalSince($0.createdAt) <= staleAfter })
        else {
            return nil
        }

        let fileCount = entry.localFileNames.count
        let noun = fileCount == 1 ? "file" : "files"
        return .progress("Uploading \(fileCount) \(noun) to \(entry.targetName)...")
    }
}
