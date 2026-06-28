import XCTest
@testable import AgentDropCore

final class ClipboardImageStagerTests: XCTestCase {
    func testStagesImageBytesAsUploadSource() throws {
        let root = try makeTemporaryDirectory()
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        let imageDrop = ClipboardImageDrop(
            remoteName: "Screenshot 2026-06-28 at 18.08.50.png",
            localDisplayName: "Screenshot 2026-06-28 at 18.08.50.png"
        )

        let staged = try ClipboardImageStager.stage(
            pngData: bytes,
            imageDrop: imageDrop,
            baseDirectory: root,
            directoryName: "fixed"
        )

        XCTAssertEqual(staged.directory, root.appendingPathComponent("fixed", isDirectory: true))
        XCTAssertEqual(staged.files, [
            UploadSourceFile(
                sourceURL: root.appendingPathComponent("fixed", isDirectory: true)
                    .appendingPathComponent("Screenshot 2026-06-28 at 18.08.50.png"),
                remoteName: "Screenshot 2026-06-28 at 18.08.50.png",
                localDisplayName: "Screenshot 2026-06-28 at 18.08.50.png",
                isDirectory: false
            )
        ])
        XCTAssertEqual(try Data(contentsOf: staged.files[0].sourceURL), bytes)

        try staged.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.directory.path))
    }

    func testCleansUpDirectoryWhenWriteFailsBecauseDirectoryNameIsAFile() throws {
        let root = try makeTemporaryDirectory()
        let blockingFile = root.appendingPathComponent("fixed")
        try Data("not a directory".utf8).write(to: blockingFile)
        let imageDrop = ClipboardImageDrop(remoteName: "Screenshot.png", localDisplayName: "Screenshot.png")

        XCTAssertThrowsError(try ClipboardImageStager.stage(
            pngData: Data([1, 2, 3]),
            imageDrop: imageDrop,
            baseDirectory: root,
            directoryName: "fixed"
        ))

        XCTAssertTrue(FileManager.default.fileExists(atPath: blockingFile.path))
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
