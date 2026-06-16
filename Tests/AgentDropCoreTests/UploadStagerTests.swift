import XCTest
@testable import AgentDropCore

final class UploadStagerTests: XCTestCase {
    func testStagesFilesUsingUniqueLocalNamesAndOriginalRemoteNames() throws {
        let root = try makeTemporaryDirectory()
        let firstSourceDirectory = root.appendingPathComponent("first", isDirectory: true)
        let secondSourceDirectory = root.appendingPathComponent("second", isDirectory: true)
        let stagingRoot = root.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: firstSourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondSourceDirectory, withIntermediateDirectories: true)
        let first = firstSourceDirectory.appendingPathComponent("demo.png")
        let second = secondSourceDirectory.appendingPathComponent("demo.png")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        let staged = try UploadStager.stage(
            files: [first, second],
            baseDirectory: stagingRoot,
            directoryName: "fixed"
        )

        XCTAssertEqual(staged.files.map(\.remoteName), ["demo.png", "demo.png"])
        XCTAssertEqual(staged.files.map(\.sourceURL.lastPathComponent), ["0-demo.png", "1-demo.png"])
        XCTAssertEqual(try String(contentsOf: staged.files[0].sourceURL), "first")
        XCTAssertEqual(try String(contentsOf: staged.files[1].sourceURL), "second")

        try staged.cleanup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.directory.path))
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
