import Foundation

public enum ClipboardImageStager {
    public static func stage(
        pngData: Data,
        imageDrop: ClipboardImageDrop,
        baseDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("AgentDropClipboard", isDirectory: true),
        directoryName: String = UUID().uuidString,
        fileManager: FileManager = .default
    ) throws -> StagedUpload {
        let directory = baseDirectory.appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        do {
            let destination = directory.appendingPathComponent(imageDrop.remoteName)
            try pngData.write(to: destination, options: .atomic)
            return StagedUpload(directory: directory, files: [
                UploadSourceFile(
                    sourceURL: destination,
                    remoteName: imageDrop.remoteName,
                    localDisplayName: imageDrop.localDisplayName,
                    isDirectory: false
                )
            ])
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }
}
