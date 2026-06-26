import Foundation

public struct StagedUpload: Equatable {
    public let directory: URL
    public let files: [UploadSourceFile]

    public func cleanup(fileManager: FileManager = .default) throws {
        try fileManager.removeItem(at: directory)
    }
}

public enum UploadStager {
    public static func stage(
        files: [URL],
        baseDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("AgentDropUploads", isDirectory: true),
        directoryName: String = UUID().uuidString,
        fileManager: FileManager = .default
    ) throws -> StagedUpload {
        let directory = baseDirectory.appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var stagedFiles: [UploadSourceFile] = []
        do {
            for (index, file) in files.enumerated() {
                let didStartAccessing = file.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing {
                        file.stopAccessingSecurityScopedResource()
                    }
                }

                let isDirectory = (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                let stagedName = "\(index)-\(file.lastPathComponent)"
                let destination = directory.appendingPathComponent(stagedName, isDirectory: isDirectory)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: file, to: destination)
                stagedFiles.append(UploadSourceFile(
                    sourceURL: destination,
                    remoteName: file.lastPathComponent,
                    localDisplayName: file.lastPathComponent,
                    isDirectory: isDirectory
                ))
            }
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }

        return StagedUpload(directory: directory, files: stagedFiles)
    }
}
