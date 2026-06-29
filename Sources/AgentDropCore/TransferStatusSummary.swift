import Foundation

public enum TransferStatusSummary: Equatable, Sendable {
    case idle
    case progress(String)
    case uploadSuccess(fileCount: Int, targetName: String, copiedPaths: Bool)
    case failure(String)

    public var systemImageName: String {
        switch self {
        case .idle:
            return "circle.fill"
        case .progress:
            return "arrow.up.circle.fill"
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
