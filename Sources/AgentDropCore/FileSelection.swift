import Foundation

public enum RejectionReason: Equatable {
    case missing
    case notRegularFile
}

public struct RejectedFile: Equatable {
    public let url: URL
    public let reason: RejectionReason
}

public struct FileSelectionResult: Equatable {
    public let files: [URL]
    public let rejected: [RejectedFile]
}

public enum FileSelection {
    public static func validate(_ urls: [URL], fileManager: FileManager = .default) -> FileSelectionResult {
        var files: [URL] = []
        var rejected: [RejectedFile] = []

        for url in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                rejected.append(RejectedFile(url: url, reason: .missing))
                continue
            }

            if isDirectory.boolValue {
                files.append(url)
                continue
            }

            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                if values.isRegularFile == true {
                    files.append(url)
                } else {
                    rejected.append(RejectedFile(url: url, reason: .notRegularFile))
                }
            } catch {
                rejected.append(RejectedFile(url: url, reason: .notRegularFile))
            }
        }

        return FileSelectionResult(files: files, rejected: rejected)
    }

    public static func cliFailureMessages(for selection: FileSelectionResult) -> [String] {
        var messages = selection.rejected.map { rejected in
            "Rejected file \(rejected.url.path): \(rejected.reason.cliDescription)"
        }

        if selection.files.isEmpty {
            messages.append("No supported files selected.")
        }

        return messages
    }
}

private extension RejectionReason {
    var cliDescription: String {
        switch self {
        case .missing:
            return "missing"
        case .notRegularFile:
            return "not a regular file"
        }
    }
}
