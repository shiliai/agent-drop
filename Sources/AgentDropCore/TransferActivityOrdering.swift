import Foundation

public enum TransferActivityOrdering {
    public static func ordered(_ entries: [UploadHistoryEntry]) -> [UploadHistoryEntry] {
        entries.sorted { lhs, rhs in
            let lhsActive = lhs.status == .running
            let rhsActive = rhs.status == .running
            if lhsActive != rhsActive { return lhsActive }

            let lhsDate = lhs.completedAt ?? lhs.createdAt
            let rhsDate = rhs.completedAt ?? rhs.createdAt
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
