import XCTest
@testable import AgentDropCore

final class FileSelectionTests: XCTestCase {
    func testAcceptsRegularFiles() throws {
        let root = try temporaryDirectory()
        let file = root.appendingPathComponent("demo.png")
        FileManager.default.createFile(atPath: file.path, contents: Data("image".utf8))

        let result = FileSelection.validate([file])

        XCTAssertEqual(result.files, [file])
        XCTAssertTrue(result.rejected.isEmpty)
    }

    func testRejectsDirectories() throws {
        let root = try temporaryDirectory()
        let directory = root.appendingPathComponent("assets")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let result = FileSelection.validate([directory])

        XCTAssertTrue(result.files.isEmpty)
        XCTAssertEqual(result.rejected.map(\.url), [directory])
        XCTAssertEqual(result.rejected.map(\.reason), [.directoryUnsupported])
    }

    func testRejectsMissingPaths() throws {
        let root = try temporaryDirectory()
        let missing = root.appendingPathComponent("missing.png")

        let result = FileSelection.validate([missing])

        XCTAssertTrue(result.files.isEmpty)
        XCTAssertEqual(result.rejected.map(\.url), [missing])
        XCTAssertEqual(result.rejected.map(\.reason), [.missing])
    }

    func testRejectsNonRegularFiles() throws {
        let root = try temporaryDirectory()
        let fifo = root.appendingPathComponent("upload.pipe")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mkfifo")
        process.arguments = [fifo.path]

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)

        let result = FileSelection.validate([fifo])

        XCTAssertTrue(result.files.isEmpty)
        XCTAssertEqual(result.rejected.map(\.url), [fifo])
        XCTAssertEqual(result.rejected.map(\.reason), [.notRegularFile])
    }
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
