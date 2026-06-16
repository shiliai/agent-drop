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

    private static func shortReason(from errorDescription: String) -> String {
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
}
