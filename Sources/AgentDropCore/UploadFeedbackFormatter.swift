import Foundation

public enum UploadFeedbackFormatter {
    public static func success(fileCount: Int, targetName: String, copiedPaths: Bool) -> String {
        let noun = fileCount == 1 ? "file" : "files"
        if copiedPaths {
            return "Uploaded \(fileCount) \(noun) to \(targetName). Path copied."
        }
        return "Uploaded \(fileCount) \(noun) to \(targetName), but could not copy paths."
    }

    public static func failure(targetName: String, errorDescription: String) -> String {
        "Upload to \(targetName) failed. \(shortReason(from: errorDescription))"
    }

    public static func shortReason(from errorDescription: String) -> String {
        if let wrappedError = parseWrappedError(from: errorDescription) {
            return trimSentence(wrappedError)
        }

        if isKnownLabeledError(errorDescription) {
            return trimSentence(errorDescription)
        }

        let quotedParts = errorDescription.split(separator: "\"", omittingEmptySubsequences: false)
        if quotedParts.count >= 2 {
            let quoted = String(quotedParts[1])
            if !quoted.isEmpty {
                return trimSentence(quoted)
            }
        }

        let beforeUserInfo = errorDescription.components(separatedBy: " UserInfo=").first ?? errorDescription
        return trimSentence(beforeUserInfo)
    }

    private static func trimSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 120 else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 117)
        return String(trimmed[..<end]) + "..."
    }

    private static func parseWrappedError(from errorDescription: String) -> String? {
        let patterns = [
            "remoteDirectoryFailed(",
            "noAvailableRemoteName(",
            "remoteExistenceCheckFailed(",
            "rsyncFailed(",
            "clipboardFailed(",
            "remoteInspectionFailed(",
            "unsupportedRemotePath(",
            "destinationReservationFailed(",
            "tarFailed("
        ]

        guard let pattern = patterns.first(where: errorDescription.hasPrefix) else {
            return nil
        }

        guard errorDescription.hasSuffix("\")") else {
            return nil
        }

        let contentStart = errorDescription.index(errorDescription.startIndex, offsetBy: pattern.count)
        let contentEnd = errorDescription.index(before: errorDescription.endIndex)
        guard contentStart <= contentEnd else {
            return nil
        }

        let wrapped = String(errorDescription[contentStart..<contentEnd])
        guard wrapped.first == "\"", wrapped.last == "\"" else {
            return nil
        }

        let quotedPayload = String(wrapped.dropFirst().dropLast())
        return quotedPayload
            .replacingOccurrences(of: #"\""#, with: #"""#)
            .replacingOccurrences(of: #"\\n"#, with: "\n")
    }

    private static func isKnownLabeledError(_ errorDescription: String) -> Bool {
        let patterns = [
            "hostHintMismatch("
        ]
        return patterns.contains { errorDescription.hasPrefix($0) }
    }
}
