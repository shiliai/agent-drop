import Foundation

public enum ClipboardFileURLSelection {
    public static func fileURLs(typedURLs: [URL], legacyFilePaths: [String]) -> [URL] {
        let fileURLs = typedURLs.filter(\.isFileURL)
        if !fileURLs.isEmpty {
            return fileURLs
        }

        return legacyFilePaths.map { URL(fileURLWithPath: $0) }
    }
}
