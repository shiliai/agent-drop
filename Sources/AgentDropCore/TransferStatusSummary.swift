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

    static func canShowRunningFinderUpload(
        currentStatus: TransferStatusSummary,
        isShowingFinderUploadStatus: Bool
    ) -> Bool {
        if isShowingFinderUploadStatus {
            return true
        }

        switch currentStatus {
        case .progress:
            return false
        case .idle, .success, .uploadSuccess, .failure:
            return true
        }
    }

    static func runningUploadHistoryEntry(
        from entries: [UploadHistoryEntry],
        now: Date = Date(),
        staleAfter: TimeInterval = defaultRunningHistoryStaleInterval
    ) -> UploadHistoryEntry? {
        entries
            .filter { $0.direction == .upload && $0.status == .running }
            .sorted { $0.createdAt > $1.createdAt }
            .first { now.timeIntervalSince($0.createdAt) <= staleAfter }
    }

    static func runningUploadHistoryStatus(
        from entries: [UploadHistoryEntry],
        now: Date = Date(),
        staleAfter: TimeInterval = defaultRunningHistoryStaleInterval
    ) -> TransferStatusSummary? {
        guard let entry = runningUploadHistoryEntry(from: entries, now: now, staleAfter: staleAfter) else {
            return nil
        }

        let fileCount = entry.localFileNames.count
        let noun = fileCount == 1 ? "file" : "files"
        return .progress("Uploading \(fileCount) \(noun) to \(entry.targetName)...")
    }
}

public struct FinderUploadStatusResolution: Equatable, Sendable {
    public let transferStatusSummary: TransferStatusSummary
    public let activeUploadID: UploadHistoryEntry.ID?
    public let isShowingFinderUploadStatus: Bool
    public let staleRefreshEntry: UploadHistoryEntry?
}

public enum FinderUploadStatusResolver {
    public static func resolve(
        entries: [UploadHistoryEntry],
        currentStatus: TransferStatusSummary,
        activeUploadID: UploadHistoryEntry.ID?,
        isShowingFinderUploadStatus: Bool,
        now: Date = Date(),
        staleAfter: TimeInterval = TransferStatusSummary.defaultRunningHistoryStaleInterval
    ) -> FinderUploadStatusResolution {
        if let runningEntry = TransferStatusSummary.runningUploadHistoryEntry(
            from: entries,
            now: now,
            staleAfter: staleAfter
        ) {
            guard TransferStatusSummary.canShowRunningFinderUpload(
                currentStatus: currentStatus,
                isShowingFinderUploadStatus: isShowingFinderUploadStatus
            ) else {
                return FinderUploadStatusResolution(
                    transferStatusSummary: currentStatus,
                    activeUploadID: nil,
                    isShowingFinderUploadStatus: false,
                    staleRefreshEntry: nil
                )
            }

            guard let runningSummary = TransferStatusSummary.runningUploadHistoryStatus(
                from: [runningEntry],
                now: now,
                staleAfter: staleAfter
            ) else {
                return FinderUploadStatusResolution(
                    transferStatusSummary: currentStatus,
                    activeUploadID: activeUploadID,
                    isShowingFinderUploadStatus: isShowingFinderUploadStatus,
                    staleRefreshEntry: nil
                )
            }

            return FinderUploadStatusResolution(
                transferStatusSummary: runningSummary,
                activeUploadID: runningEntry.id,
                isShowingFinderUploadStatus: true,
                staleRefreshEntry: runningEntry
            )
        }

        guard isShowingFinderUploadStatus else {
            return FinderUploadStatusResolution(
                transferStatusSummary: currentStatus,
                activeUploadID: nil,
                isShowingFinderUploadStatus: false,
                staleRefreshEntry: nil
            )
        }

        let resolvedStatus: TransferStatusSummary
        if let activeUploadID,
           let completedEntry = entries.first(where: { $0.id == activeUploadID }) {
            switch completedEntry.status {
            case .succeeded:
                let fileCount = completedEntry.localFileNames.count
                let noun = fileCount == 1 ? "file" : "files"
                resolvedStatus = .success("Uploaded \(fileCount) \(noun) to \(completedEntry.targetName).")
            case .failed:
                resolvedStatus = .failure(
                    completedEntry.errorMessage ?? "Upload to \(completedEntry.targetName) failed."
                )
            case .running:
                resolvedStatus = .idle
            }
        } else {
            resolvedStatus = .idle
        }

        return FinderUploadStatusResolution(
            transferStatusSummary: resolvedStatus,
            activeUploadID: nil,
            isShowingFinderUploadStatus: false,
            staleRefreshEntry: nil
        )
    }
}
