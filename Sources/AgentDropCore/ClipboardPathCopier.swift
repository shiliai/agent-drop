import Foundation

public enum ClipboardPathCopyResult: Equatable, Sendable {
    case copied
    case failed(String)
}

public enum ClipboardPathCopier {
    public static func copyRemotePaths(
        from uploaded: [UploadedFile],
        clipboard: ClipboardWriting = PBClipboardWriter()
    ) -> ClipboardPathCopyResult {
        do {
            try clipboard.write(uploaded.map(\.remoteDisplayPath).joined(separator: "\n"))
            return .copied
        } catch {
            return .failed(clipboardFailureReason(from: error))
        }
    }

    private static func clipboardFailureReason(from error: Error) -> String {
        if case let ClipboardError.writeFailed(reason) = error {
            return reason
        }
        return String(describing: error)
    }
}
