import Foundation

public enum TransferFileSize {
    public static func byteCount(of urls: [URL], fileManager: FileManager = .default) -> Int64? {
        var total: Int64 = 0
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]) else { return nil }
            if values.isDirectory == true {
                var didFail = false
                guard let enumerator = fileManager.enumerator(
                    at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                    errorHandler: { _, _ in didFail = true; return false }
                ) else { return nil }
                for case let file as URL in enumerator {
                    guard let attributes = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else { return nil }
                    if attributes.isRegularFile == true {
                        guard let size = attributes.fileSize else { return nil }
                        total += Int64(size)
                    }
                }
                if didFail { return nil }
            } else if values.isRegularFile == true, let size = values.fileSize {
                total += Int64(size)
            } else {
                return nil
            }
        }
        return total
    }
}
